# frozen_string_literal: true

module SlimLint
  # Checks for uses of the `div` tag where a class name or ID shortcut was used.
  class Linter::RedundantDiv < Linter
    include LinterRegistry

    SHORTCUT_ATTRS = %w[id class]
    IMPLICIT_MESSAGE = "`div` is redundant when %s attribute shortcut is present"
    EXPLICIT_MESSAGE = "Use an explicit `div` rather than a standalone %s attribute shortcut"

    on [:html, :tag, anything, capture(:attrs, [:html, :attrs]), anything] do |sexp|
      _, _, name, value = captures[:attrs][2]
      next unless name
      next unless value[0] == :static
      next unless SHORTCUT_ATTRS.include?(name.value)

      case config["style"]
      when "implicit", "never", false, nil
        report_lint(sexp[2], IMPLICIT_MESSAGE % name) if sexp[2].value == "div"
      when "explicit", "always", true
        report_lint(sexp[2], EXPLICIT_MESSAGE % name) if sexp[2].value =~ /[#.]/
      else
        raise ArgumentError, "Unknown value for `style`; please use 'implicit' or 'explicit'"
      end
    end
  end
end
