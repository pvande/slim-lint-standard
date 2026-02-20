# Linter Differences

This document analyzes the differences between three versions of the slim-lint codebase:

- **Merge base**: [sds/slim-lint v0.22.1](https://github.com/sds/slim-lint/releases/tag/v0.22.1) — the commit from which this project was forked (git SHA `2921154`)
- **This project**: [pvande/slim-lint-standard](https://github.com/pvande/slim-lint-standard) HEAD — the current state of this fork
- **sds upstream**: [sds/slim-lint](https://github.com/sds/slim-lint) HEAD (v0.34.0) — the current state of the original project

---

## Changes: This Project vs. Merge Base (v0.22.1)

### Identity and Packaging

- **Renamed**: gem is now `slim_lint_standard` (was `slim_lint`), binary is `slim-lint-standard` (was `slim-lint`)
- **New dependency**: `standard` gem (StandardRB) added as a runtime dependency
- **New dependency**: `rexml` added as a runtime dependency
- **Removed files**: `.overcommit.yml`, `.rubocop.yml` — opinionated developer tooling stripped out in favor of StandardRB
- **Version**: reset to `0.0.3.4` (from `0.22.1`)
- **Ruby requirement**: `>= 2.6.0` (unchanged)

### New Linters

| Linter | Description |
|--------|-------------|
| `Standard` | Runs [StandardRB](https://standardrb.com/) on extracted Ruby code instead of raw RuboCop. Extends the existing `RuboCop` linter class and uses `Standard::Cli` rather than `RuboCop::CLI`. Enabled by default. |
| `AvoidMultilineExpressions` | Reports control statements (`-`), dynamic output expressions (`=`/`==`), dynamic attribute values, and splat attributes whose Ruby code spans multiple lines (i.e., uses line continuation with `,` or `\`). Enabled by default. |
| `DynamicOutputSpacing` | Checks for missing or superfluous whitespace before and after dynamic tag output indicators (`=`, `==`). Configurable via `space_before` and `space_after` options (`never`, `always`, `ignore`). Enabled by default with `space_before: always, space_after: always`. |

### Modified Linters

**`RuboCop`** (restructured):
- Class nesting changed from `class Linter::RuboCop` to `class Linter; class RuboCop` to allow `Standard` to inherit from it cleanly
- `lint_file` now takes only a filename (no `rubocop` argument); a `RuboCop::CLI` instance is no longer passed in
- `extract_lints_from_offenses` now accepts a two-element array as the linter identity `[self, offense.cop_name]` to surface cop names in lint output, and strips location suffixes from messages
- `rubocop_flags` updated to use `--stdin` and `--no-display-cop-names`

**`ControlStatementSpacing`** (substantially reworked):
- In the merge base, this linter only checked for spacing around `=` in output expressions on tags
- In this fork, it checks only control statement (`-`) spacing, with a configurable `space_after` option (`never`, `always`, `ignore`); the output-expression spacing check was split off into the new `DynamicOutputSpacing` linter
- Default config adds `space_after: always`

**`RedundantDiv`**:
- Default config adds `style: implicit`

**`LineLength`**:
- Disabled by default in this fork (was enabled at 80 chars in the merge base)

**`RuboCop`**:
- Disabled by default (enabled in merge base); users are expected to use `Standard` instead

### Architectural Changes: Parse Tree and S-Expression System

This is the deepest change in the fork. The entire parse tree representation was overhauled to carry full source location information (line and column, not just line number) on every node:

**`Sexp`** (`lib/slim_lint/sexp.rb`):
- Changed from `attr_accessor :line` (a single integer) to `attr_accessor :start, :finish` (each a `[line, column]` pair)
- `initialize` now takes keyword args `start:` and `finish:` and propagates them to child nodes
- Added `column` accessor, `location` method (returns a `SourceLocation`), and `to_array` method

**`Atom`** (`lib/slim_lint/atom.rb`):
- Changed from `attr_accessor :line` to `attr_accessor :value, :start, :finish`
- Constructor now requires a `pos:` keyword argument
- Added `line`, `location`, `to_array`, and `inspect` methods
- `inspect` now shows positional range (`A(1:3 => 1:8) "foo"`)

**`SourceLocation`** (new file: `lib/slim_lint/source_location.rb`):
- New class encapsulating `start_line`, `start_column`, `last_line`, `last_column`, and `length`
- Provides `adjust(line:, column:)` for offset arithmetic, `as_json`, and `SourceLocation.merge`

**`Engine`** (`lib/slim_lint/engine.rb`):
- Removed the `SexpConverter` and `InjectLineNumbers` filters; position information is now embedded directly by the parser itself (see Parser section below)
- Now uses `SlimLint::Parser` directly rather than `Slim::Parser`

**`Filter`** (`lib/slim_lint/filter.rb`) — new file:
- Provides an alternative base class to `Slim::Filter` / `Temple::HTML::Filter` that preserves Sexp position data when transforming nodes (the upstream filters mutate nodes by replacing them, which can drop position info)

### Architectural Changes: Custom Parser

The merge base used `Slim::Parser` directly via the engine. This fork introduces its own `SlimLint::Parser < Slim::Parser` (`lib/slim_lint/parser.rb`) that overrides key methods to produce `Sexp` and `Atom` objects with embedded position data instead of plain Ruby arrays. See `PARSER-DIFF.md` for a detailed analysis of this parser.

### Architectural Changes: Ruby Extraction Pipeline

**`RubyExtractEngine`** (`lib/slim_lint/ruby_extract_engine.rb`) — substantially changed:
- Now uses `SlimLint::Parser` (not `Slim::Parser`)
- Runs additional filters in sequence: `Interpolation`, `SplatProcessor`, `DoInserter`, `EndInserter`, `AutoIndenter`, `ControlProcessor`, `AttributeProcessor`, `MultiFlattener`, `StaticMerger`
- These filters are newly added to the fork (see below)

**New filters** (all under `lib/slim_lint/filters/`):
- `AutoIndenter` — applies indent/outdent markers to code nodes
- `DoInserter` — inserts `do` keywords before block-opening control statements (from Slim's own pipeline)
- `EndInserter` — inserts `end` keywords to close blocks (from Slim's own pipeline)
- `Interpolation` — handles string interpolation in text blocks (from Slim's own pipeline)
- `MultiFlattener` — flattens `:multi` nodes with single children (from Slim's own pipeline)
- `StaticMerger` — merges adjacent `:static` nodes (from Slim's own pipeline)

**Removed filters**:
- `SexpConverter` — no longer needed; parser produces `Sexp`/`Atom` objects directly
- `InjectLineNumbers` — no longer needed; position info is embedded at parse time

**`RubyExtractor`** (`lib/slim_lint/ruby_extractor.rb`) — substantially reworked:
- Now tracks `@indent` level for proper Ruby indentation in extracted code
- Handles `[:html, :attr]` by wrapping attribute value code in `attribute("name") do ... end`
- Handles `[:dynamic]` by wrapping output code in `output do ... end`
- Handles `[:interpolated]` by wrapping in `p "x#{...}x"`
- Handles `[:slim, :embedded]` with `ruby:` block by extracting static code directly
- `append` now raises on unexpected newlines and prepends indentation
- Added `append_dynamic`, `append_interpolated` helpers with adjusted column mappings
- Source map now stores `SourceLocation` values (not plain integers)

### Default Configuration Changes (`config/default.yml`)

| Setting | Merge Base | This Fork |
|---------|-----------|-----------|
| `AvoidMultilineExpressions` | absent | enabled |
| `ControlStatementSpacing.space_after` | absent | `always` |
| `DynamicOutputSpacing` | absent | enabled, `space_before: always`, `space_after: always` |
| `LineLength` | enabled (max: 80) | disabled |
| `RedundantDiv.style` | absent | `implicit` |
| `RuboCop` | enabled | disabled |
| `Standard` | absent | enabled |

---

## Changes: sds/slim-lint HEAD (v0.34.0) vs. Merge Base (v0.22.1)

### New Linters

| Linter | Description |
|--------|-------------|
| `InstanceVariables` | Reports instance variables (e.g. `@foo`) found in extracted Ruby code from templates. Disabled by default; configured to match partial templates (`app/views/**/_*.html.slim`). |
| `QuoteConsistency` | Checks that all HTML attribute values on a given line use the same quote style (single or double). Configurable via `enforced_style` option (default: `single_quotes`). Disabled by default. |
| `StrictLocalsMissing` | Reports templates that do not contain a strict locals magic comment (`/# locals: (...)`). Disabled by default; configured to match partials. |
| `Tag` | Reports use of forbidden HTML tags (e.g. `<script>`). Configurable via `forbidden_tags` list. Disabled by default. |
| `TagAttribute` | Reports use of forbidden HTML attributes (e.g. `onclick`). Configurable via `forbidden_attributes` list. Disabled by default. |
| `Zwsp` | Reports lines containing zero-width space characters (U+200B). Enabled by default. |

### Modified Linters

**`ControlStatementSpacing`**:
- Added a check for control statements (`-`): reports if there is no space after the dash
- Added a `MESSAGE_CONTROL` constant; the existing `MESSAGE` constant was renamed to `MESSAGE_OUTPUT`

**`RuboCop`**:
- `RuboCop::CLI` is now instantiated once in `initialize` and reused across calls (instead of creating a new instance per `find_lints` call)
- `lint_file` signature changed to take only a filename (the `rubocop` argument was removed)
- Added `require 'stringio'` to support RuboCop's StringIO-based stdin processing

**`LinterRegistry`**:
- Added `linter_names` class method returning short linter names (last component of `::`)-separated name)
- Refactored `extract_linters_from` to use a more idiomatic rescue at the method level instead of begin/rescue inside a block

### New Reporter

**`GithubReporter`** (`lib/slim_lint/reporter/github_reporter.rb`):
- Outputs lints as GitHub Actions workflow commands (`::error` / `::warning`) suitable for annotation in pull request diffs

### Infrastructure / CI

- Travis CI (`.travis.yml`) replaced by GitHub Actions (`.github/workflows/test.yml`)
- Added Ruby 3.x and 3.4 support; dropped Ruby 3.0 (EOL)
- Added `.rubocop_todo.yml`

### Default Configuration Changes (`config/default.yml`)

| Setting | Merge Base | sds HEAD |
|---------|-----------|----------|
| `InstanceVariables` | absent | disabled (partials only) |
| `StrictLocalsMissing` | absent | disabled (partials only) |
| `Tag` | absent | disabled, `forbidden_tags: []` |
| `TagAttribute` | absent | disabled, `forbidden_attributes: []` |
| `QuoteConsistency` | absent | disabled |
| `Zwsp` | absent | disabled |

---

## Summary: Divergence Between the Two Forks

The two forks have diverged in substantially different directions from the v0.22.1 merge base.

**This fork** (`pvande/slim-lint-standard`) made architectural changes throughout the codebase to support precise column-level source location tracking, a prerequisite for the new StandardRB integration and spacing linters. The parser was replaced with a custom subclass of `Slim::Parser`, the Sexp/Atom representation was extended to carry `[line, column]` pairs, and the Ruby extraction pipeline was rebuilt around a richer set of Temple filters. Three new linters oriented around StandardRB and Slim-specific style conventions were added.

**sds/slim-lint** (`sds/slim-lint`) stayed closer to the original architecture but added six new linters covering a different set of concerns (instance variables, quote style, zero-width spaces, strict locals, and forbidden tags/attributes), upgraded CI infrastructure, and added a GitHub Actions reporter.

The two forks share no new linters in common. Merging them would require reconciling the deep structural differences in the Sexp/Atom/location system before any new linter code could be shared.
