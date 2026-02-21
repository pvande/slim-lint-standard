# frozen_string_literal: true

module SlimLint
  # Reports on missing strict locals magic comment in Slim templates.
  #
  # Strict locals look like:
  #   /# locals: (name:, other_name: default_value)
  class Linter::StrictLocalsMissing < Linter
    include LinterRegistry

    on_start do |_sexp|
      unless document.source =~ %r{/#\s+locals:\s+\(.*\)}
        sexp = Sexp.new(:dummy, start: [1, 0], finish: [1, 0])
        report_lint(sexp, "Strict locals magic comment is missing")
      end
    end
  end
end
