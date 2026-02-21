# frozen_string_literal: true

module SlimLint
  # Checks for zero-width space characters (U+200B), which are invisible but
  # can cause unexpected behavior and are difficult to spot.
  class Linter::Zwsp < Linter
    include LinterRegistry

    MSG = "Remove zero-width space"

    on_start do |_sexp|
      document.source_lines.each.with_index(1) do |line, lineno|
        col = line.index("\u200b")
        next unless col

        sexp = Sexp.new(:dummy, start: [lineno, col], finish: [lineno, col + 1])
        report_lint(sexp, MSG)
      end
    end
  end
end
