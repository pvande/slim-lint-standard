# Parser Differences

This document analyzes the differences between three versions of the Slim parser:

- **Baseline**: [`slim-template/slim` v4.1.0](https://github.com/slim-template/slim/tree/v4.1.0) — the Slim gem release at the time of the slim-lint fork (tag `v4.1.0`)
- **This project**: `SlimLint::Parser` in `lib/slim_lint/parser.rb` — the custom parser embedded in this fork
- **Slim upstream**: [`slim-template/slim` HEAD](https://github.com/slim-template/slim) (`main` branch) — the current state of the Slim gem

---

## This Project's Parser vs. slim-template/slim v4.1.0

### Design Intent

This fork does not vendor a copy of `Slim::Parser`. Instead, `SlimLint::Parser` inherits from `Slim::Parser` and overrides specific methods with the minimum changes needed to produce a richer parse tree. The class comment says:

> This version of the Slim::Parser makes the smallest changes it can to preserve newline information through the parse. This helps us keep better track of line numbers.

The core goal is that every node in the resulting S-expression carries `start` and `finish` position data as `[line, column]` pairs, enabling linters to report precise column-level locations and compare multi-line spans. This is in contrast to the original `Slim::Parser`, which produces plain Ruby arrays with no position information at all.

### What Is Inherited Unchanged

Because `SlimLint::Parser < Slim::Parser`, the following are fully inherited from the installed Slim gem and are not overridden:

- `initialize` (option parsing, regex compilation, shortcut setup)
- `get_indent`
- All tag shortcut and attribute shortcut regular expression construction

This means the fork's parser will track the behavior of whichever version of the `slim` gem is installed at runtime. The gemspec pins `slim` to `>= 3.0, < 5.0`, so any Slim 3.x or 4.x parser behavior is supported.

### Summary of Changes (272 insertions, 236 deletions — net +36 lines)

#### Class and Module Wrapping

- **Before**: `module Slim; class Parser < Temple::Parser`
- **After**: `module SlimLint; class Parser < Slim::Parser`

The options hash is inherited via `@options = Slim::Parser.options` at the class level rather than re-declaring them. The inner `SyntaxError` class, constructor, and all option-parsing logic are removed because they are inherited.

#### Stack Management: Functional Change

The original Slim parser uses a mutable global stack passed into `reset`:

```ruby
# v4.1.0
def call(str)
  result = [:multi]
  reset(str.split(/\r?\n/), [result])
  parse_line while next_line
  reset
  result
end

def reset(lines = nil, stacks = nil)
  @stacks = stacks
  ...
end
```

This fork replaces this with explicit `push`/`pop`/`append` methods that also update position information:

```ruby
# slim_lint/parser.rb
def call(str)
  reset(str.split(/\r?\n/))
  push create_container(sexp(:multi, start: [1, 1]))
  parse_line while next_line
  result = pop until @stacks.empty?
  reset
  result
end

def push(sexp)   @stacks << sexp                           end
def pop          @stacks.last.finish = pos; @stacks.pop    end
def append(sexp) @stacks.last << sexp                      end
```

`pop` records `finish` position on the sexp being closed. `reset` no longer takes a `stacks` argument; the stack always starts empty.

#### Line Tracking: Added `@prev_line`

`next_line` now saves the previous line before advancing:

```ruby
def next_line
  @prev_line = @orig_line  # NEW
  if @lines.empty?
    @orig_line = @line = nil
  else
    ...
  end
end
```

`@prev_line` is available for context but is not directly used by methods shown in the diff; it is available to subclasses or future methods.

`reset` similarly initializes `@prev_line`:
```ruby
@prev_line = @line = @orig_line = nil  # was: @line = @orig_line = nil
```

#### Blank Line Handling: Compile-Time Regex

A named constant replaces an inline literal:

```ruby
BLANK_LINE_RE = /\A\s*\Z/
```

`parse_line` uses this constant in its guard:
```ruby
if @line =~ BLANK_LINE_RE
```

The original checked inline with `@lines.first =~ /\A\s*\Z/` inside `parse_text_block`. Additionally, the blank line check in the tag content section was changed to use the constant (`when BLANK_LINE_RE`) instead of `when /\A\s*\Z/`.

#### `:newline` Nodes Removed

The original Slim parser inserts `[:newline]` S-expression nodes in several places:
- After every `parse_line` call (at the end of `parse_line`)
- Inside `parse_text_block` for blank lines
- Inside `parse_attributes` when attributes span multiple lines

This fork removes all `:newline` insertions. Position information is tracked directly on nodes via `start`/`finish` pairs, so the `:newline` sentinels are no longer needed for line accounting. This changes the shape of the generated S-expression tree.

#### `parse_text_block`: Added `type` Parameter and `sexp` Wrappers

**v4.1.0 signature**: `parse_text_block(first_line = nil, text_indent = nil)`
**Fork signature**: `parse_text_block(type, first_line = nil, text_indent = nil)`

The `type` parameter is a partial S-expression prefix (e.g., `[:slim, :interpolate]` or `[:static]`) that determines what kind of node each text line is wrapped in. In v4.1.0 this was hardcoded to `[:slim, :interpolate, ...]`.

The fork's implementation:
- Creates a `sexp(:multi, ...)` root with a starting position
- Wraps each line as `sexp(*type, line_content, width: ...)` instead of `[:slim, :interpolate, content]`
- Replaces the `empty_lines` counter and `[:slim, :interpolate, "\n" * n]` accumulation with a simpler `sexp(*type, "")` for each blank line
- Strips leading indentation by calling `@line.slice!(0, indent - offset)` instead of building the string with `(' ' * offset) + @line`
- Sets `result.finish = pos` explicitly before returning

#### `parse_broken_line`: Returns a `sexp(:multi)` of Code Nodes

**Before**:
```ruby
def parse_broken_line
  broken_line = @line.strip
  while broken_line =~ /[,\\]\Z/
    expect_next_line
    broken_line << "\n" << @line
  end
  broken_line  # returns a String
end
```

**After**:
```ruby
def parse_broken_line
  result = sexp(:multi)
  ws = @orig_line[/\A[ \t]*/].size
  @line.lstrip!
  leader = column - ws - 1
  indent = @indents.last + leader

  result << sexp(:code, @line, width: @line.chomp.size)
  while @line.strip =~ /[,\\]\Z/
    expect_next_line
    @line.slice!(0, indent)
    result << sexp(:code, @line, width: @line.chomp.size)
  end

  result  # returns a Sexp
end
```

Instead of returning a multi-line string with embedded newlines, the fork returns a `sexp(:multi)` containing one `sexp(:code, ...)` per physical line, each with its own position information. Each continuation line has leading indentation stripped to `indent` characters.

#### `parse_tag`: Added `tag_start` Parameter

**Before**: `def parse_tag(tag)` — no position tracking for the tag itself
**After**: `def parse_tag(tag_name, tag_start)` — receives `tag_start = pos` from the call site

Inside `parse_tag`, all plain array literals like `[:html, :attrs]`, `[:html, :attr, ...]`, `[:static, ...]`, `[:multi]` are replaced with `sexp(...)` calls. Nested tag parsing now uses `push content` / `parse_tag($&, tag_start)` / `pop` instead of directly manipulating `@stacks`.

#### `parse_attributes`: All Arrays Replaced with `sexp(...)` Calls

Every construction of attribute S-expression nodes is updated:

| Before | After |
|--------|-------|
| `[:html, :attrs]` | `sexp(:html, :attrs)` |
| `[:html, :attr, name, [...]]` | `sexp(:html, :attr, name, sexp(...))` |
| `[:html, :attr, $1, [:multi]]` | `sexp(:html, :attr, $1, sexp(:multi))` |
| `[:slim, :splat, code]` | `sexp(:slim, :splat)` + `capture` |
| `[:slim, :attrvalue, escape, value]` | `sexp(:slim, :attrvalue, ...)` + `capture` |
| `[:escape, flag, [:slim, :interpolate, val]]` | `sexp(:escape, ...)` + `sexp(:slim, :interpolate)` with position |

The `attributes || [:html, :attrs]` fallback at the end of the attribute loop is removed; `attributes` is always a `sexp(:html, :attrs)` and is always returned.

The `[:newline]` push inside the "attributes span multiple lines" branch is also removed.

Quoted attribute parsing now uses a `capture` pattern to record start/finish positions on the interpolated value.

Code attribute parsing now uses a `capture(attr_value)` wrapper around `parse_ruby_code`.

#### `parse_ruby_code`: Returns a `sexp(:multi)` of Code Nodes

**Before**:
```ruby
def parse_ruby_code(outer_delimiter)
  code, count, delimiter, close_delimiter = '', 0, nil, nil
  end_re = /\A[\s#{...}]/
  until @line.empty? || (count == 0 && @line =~ end_re)
    if @line =~ /\A[,\\]\Z/
      code << @line << "\n"
      expect_next_line
    else
      ...
      code << @line.slice!(0)
    end
  end
  code  # returns a flat String
end
```

**After**:
```ruby
def parse_ruby_code(outer_delimiter)
  result = sexp(:multi)
  count, delimiter, close_delimiter = 0, nil, nil
  end_re = /\A[\s#{...}]/
  indent = column
  code = ""
  until @line.empty? || (count == 0 && @line =~ end_re)
    if @line == "," || @line == "\\"
      code << @line
      result << sexp(:code, code, start: [@lineno, indent], width: code.size)
      expect_next_line
      code = ""
      @line.sub!(/\A {,#{indent - 1}}/, "")
    else
      ...
      code << @line.slice!(0)
    end
  end
  result << sexp(:code, code, start: [@lineno, indent], width: code.size)
  result.finish = result.last.finish
  result  # returns a Sexp
end
```

Each line of a multi-line Ruby expression becomes a separate `sexp(:code, ...)` with its own position. The continuation-line indentation (`indent - 1` leading spaces) is stripped before each continuation.

#### `parse_quoted_attribute`: Returns an `Atom` with Position

**Before**:
```ruby
def parse_quoted_attribute(quote)
  value, count = '', 0
  until count == 0 && @line[0] == quote[0]
    ...
  end
  @line.slice!(0)  # consume closing quote
  value  # returns a String
end
```

**After**:
```ruby
def parse_quoted_attribute(quote)
  @line.slice!(0)  # consume opening quote (moved here from callers)
  start_pos = pos
  value, count = "", 0
  until count == 0 && @line[0] == quote[0]
    if @line =~ /\A(\\)?\Z/
      value << ($1 ? " " : "\n")
      expect_next_line
      @line.strip!  # NEW: strips whitespace on continuation
    else
      ...
    end
  end
  atom(value, pos: start_pos)  # returns an Atom instead of a String
ensure
  @line.slice!(0)  # consume closing quote (moved to ensure block)
end
```

The opening-quote slice is moved into this method from the caller. The result is now an `Atom` carrying the starting column of the attribute value. A continuation-line `@line.strip!` is added (the original did not strip on continuation).

#### `expect_next_line`: Does Not Strip the Next Line

**Before**:
```ruby
def expect_next_line
  next_line || syntax_error!('Unexpected end of file')
  @line.strip!  # was stripped here
end
```

**After**:
```ruby
def expect_next_line
  next_line || syntax_error!("Unexpected end of file")
  @line  # returned as-is; callers are responsible for their own stripping
end
```

Stripping was moved out because different callers need different behavior. `parse_quoted_attribute` strips; `parse_broken_line` slices a specific amount.

#### `syntax_error!`: Column Calculation Fixed

**Before**:
```ruby
raise SyntaxError.new(message, options[:file], @orig_line, @lineno,
                      @orig_line && @line ? @orig_line.size - @line.size : 0)
```

**After**:
```ruby
raise SyntaxError.new(message, options[:file], @orig_line, @lineno, column)
```

`column` is a new helper method:

```ruby
def column
  1 + (@orig_line&.size || 0) - (@line&.size || 0)
end
```

The column is now 1-based (the original was 0-based in this calculation), consistently defined in one place, and nil-safe via `&.`.

#### `deprecated_syntax`: Quote Style Only

The `deprecated_syntax` method's column calculation was updated to use the new `column` helper, and the string style was changed from `%{...}` to `%(...)`. No behavioral change.

#### New Helper Methods

The fork adds the following private helper methods that do not exist in the original:

| Method | Description |
|--------|-------------|
| `pos` | Returns `[@lineno, column]` as the current position |
| `column` | Returns `1 + orig_line.size - line.size` (1-based current column) |
| `sexp(*args, start:, finish:, width:, lines:)` | Constructs a `SlimLint::Sexp` with position data |
| `atom(value, pos:)` | Constructs a `SlimLint::Atom` with position data |
| `capture(sexp)` | Wraps a block; assigns the yielded result into `sexp` and records `finish` |
| `create_container(sexp)` | Adds a `finish` singleton method that delegates to `last.finish` |
| `contains(container, content)` | Creates a container and pushes one content sexp into it |

#### `parse_line`: Removal of `:newline` and Inline Array Literals

At the end of `parse_line` in v4.1.0:
```ruby
@stacks.last << [:newline]
```
This line is removed entirely. Position information on each sexp eliminates the need for this sentinel.

All inline literal array constructions throughout `parse_line` are replaced with `sexp(...)` calls with position tracking.

---

## slim-template/slim HEAD vs. v4.1.0

The Slim gem itself has continued to evolve. Between v4.1.0 and the current HEAD of the `main` branch, the following changes were made to `lib/slim/parser.rb` (65 lines changed, net -13):

### Frozen String Literal

`# frozen_string_literal: true` was added at the top of the file. Several mutable string literals (`''`) were changed to `''.dup` (e.g. in `parse_ruby_code` and `parse_quoted_attribute`) to remain mutable under frozen string literals.

### Attribute Shortcut: Proc Support

```ruby
# v4.1.0
@attr_shortcut[k] = [v[:attr]].flatten

# HEAD
@attr_shortcut[k] = v[:attr].is_a?(Proc) ? v[:attr] : [v[:attr]].flatten
```

Shortcuts can now accept a `Proc` as the `:attr` value. The Proc is called with the matched shortcut text and expected to return an array of `[attr_name, value]` pairs:

```ruby
# v4.1.0
shortcut.each {|a| attributes << [:html, :attr, a, [:static, $2]] }

# HEAD
if shortcut.is_a?(Proc)
  shortcut.call($2).each { |a, v| attributes << [:html, :attr, a, [:static, v]] }
else
  shortcut.each {|a| attributes << [:html, :attr, a, [:static, $2]] }
end
```

The corresponding sort-by block style was updated to use `{ }` instead of `{|k|}`.

### Regexp Escape Fix

```ruby
# v4.1.0
@attr_name = "\\A\\s*([^\0\s#{keys}]+)"

# HEAD
@attr_name = "\\A\\s*([^\\0\\s#{keys}]+)"
```

The null byte `\0` inside a double-quoted string was previously passed as a literal null (ASCII 0) into the regex character class. It is now properly escaped as `\\0` (the two-character sequence `\0` in the regex), which matches the character class escape for null in regex syntax.

### String Concatenation: `<<` Replaced with `+`

```ruby
# v4.1.0
splat_regexp_source = '\A\s*' << splat_prefix << '(?=[^\s]+)'

# HEAD
splat_regexp_source = '\A\s*' + splat_prefix + '(?=[^\s]+)'
```

Using `+` instead of `<<` avoids mutating the string literal.

### Verbatim Text Block: Leading Whitespace Support (`|<` and `|>`)

```ruby
# v4.1.0
when /\A([\|'])( ?)/
  trailing_ws = $1 == "'"
  @stacks.last << [:slim, :text, :verbatim, parse_text_block($', @indents.last + $2.size + 1)]
  @stacks.last << [:static, ' '] if trailing_ws

# HEAD
when /\A([\|'])([<>]{1,2}(?: |\z)| ?)/
  leading_ws = $2.include?('<')
  trailing_ws = ($1 == "'") || $2.include?('>')
  @stacks.last << [:static, ' '] if leading_ws
  @stacks.last << [:slim, :text, :verbatim, parse_text_block($', @indents.last + $2.count(' ') + 1)]
  @stacks.last << [:static, ' '] if trailing_ws
```

The verbatim text block indicator now supports `|<` (add leading whitespace), `|>` (add trailing whitespace), `|<>` or `|><` (both), in addition to the existing `'` shorthand for trailing whitespace. The indentation offset calculation uses `$2.count(' ')` instead of `$2.size` so that the `<`/`>` characters themselves don't count toward the indent.

### Output Block: Removed `='` Deprecated Syntax

```ruby
# v4.1.0
when /\A=(=?)(['<>]*)/
  ...
  if $2.include?('\''.freeze)
    deprecated_syntax '=\' for trailing whitespace is deprecated in favor of =>'
    trailing_ws = true
  end

# HEAD
when /\A=(=?)([<>]*)/
  ...
  # (deprecated_syntax call removed)
```

The `'` character is no longer accepted in the output modifier string. The regex was simplified to `[<>]*` (no more `'`). The `deprecated_syntax` call for `='` was removed.

### Tag Output: Removed `='` and Tag `'` Deprecated Syntax

Similarly, tag inline output (`tag=`) no longer accepts `='`:

```ruby
# v4.1.0
if $2.include?('\''.freeze)
  deprecated_syntax '=\' for trailing whitespace is deprecated in favor of =>'
  trailing_ws2 = true
end
```

And tag trailing-whitespace shorthand no longer accepts `tag'`:

```ruby
# v4.1.0
@line =~ /\A[<>']*/
...
if $&.include?('\''.freeze)
  deprecated_syntax 'tag\' for trailing whitespace is deprecated in favor of tag>'
  trailing_ws = true
end

# HEAD
@line =~ /\A[<>']*/  # regex unchanged but deprecated_syntax block removed
```

The `deprecated_syntax` method itself was removed entirely from HEAD.

### Engine: New Filters Added

In `lib/slim/engine.rb`, the HEAD adds two new filters after the HTML Pretty filter:
- `filter :Ambles` — handles leading/trailing content ambles
- `filter :StaticAnalyzer` — performs static analysis on the expression tree

These are part of Temple's filter pipeline and do not affect the parser directly.

---

## Relationship Between the Two Diffs

The local `SlimLint::Parser` was written against `Slim::Parser` at approximately v4.1.0. The key behavioral changes introduced by the fork (all the `sexp()`/`atom()` wrapping, the position tracking, the `parse_ruby_code` returning a multi-node sexp) are orthogonal to the changes made in the Slim gem since v4.1.0.

The most significant compatibility question is the **`expect_next_line` stripping behavior**: the Slim gem HEAD still has `@line.strip!` in `expect_next_line`, while the fork removed it. Since the fork inherits from whatever Slim is installed at runtime rather than vendoring the parser, this method is not overridden in the fork — the inherited `expect_next_line` behavior will vary with the installed Slim version. In practice, the fork's callers of `expect_next_line` (`parse_broken_line` and `parse_quoted_attribute`) do their own whitespace management, so the behavior difference is mostly absorbed.

The **Proc shortcut support** and **`|<` leading-whitespace** feature added in Slim HEAD are not reflected in the fork's `parse_line` override, which still matches `when /\A([|'])( ?)/` without the `<>` modifiers. This means templates using `|<` or `|>` verbatim text modifiers would not be handled correctly if parsed through `SlimLint::Parser`.
