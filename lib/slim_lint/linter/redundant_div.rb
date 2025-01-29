# frozen_string_literal: true

module SlimLint
  # Checks for unnecessary uses of the `div` tag where a class name or ID
  # already implies a div.
  class Linter::RedundantDiv < Linter
    include LinterRegistry

    SHORTCUT_ATTRS = %w[id class]
    IMPLICIT_MESSAGE = "`div` is redundant when %s attribute shortcut is present"
    EXPLICIT_MESSAGE = "explicit `div` is preferred over bare %s attribute"

    on [:html, :tag, capture(:tag, anything), capture(:attrs, [:html, :attrs]), anything] do |sexp|
      case @config["EnforcedStyle"]
      when "implicit", :implicit
        _, _, name, value = captures[:attrs][2]
        next unless captures[:tag] == "div"
        next unless name
        next unless value[0] == :static
        next unless SHORTCUT_ATTRS.include?(name.value)
        report_lint(sexp[2], IMPLICIT_MESSAGE % name)
      when "explicit", :explicit
        next unless captures[:tag] == "." || captures[:tag] == "#"
        report_lint(sexp[2], EXPLICIT_MESSAGE % captures[:tag])
      end
    end
  end
end
