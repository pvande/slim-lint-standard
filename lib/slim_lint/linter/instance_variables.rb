# frozen_string_literal: true

require "slim_lint/ruby_extractor"
require "slim_lint/ruby_extract_engine"

module SlimLint
  # Searches for instance variables in templates.
  #
  # Instance variables in templates create tight coupling between views and
  # controllers, making them harder to test and reuse. Prefer passing locals
  # explicitly.
  #
  # Since the fork's source_map carries SourceLocation values (not bare line
  # numbers), lint reports include the exact column of the instance variable
  # within the original Slim source.
  class Linter::InstanceVariables < Linter
    include LinterRegistry

    on_start do |_sexp|
      processed_sexp = SlimLint::RubyExtractEngine.new.call(document.source)

      extractor = SlimLint::RubyExtractor.new
      extracted_source = extractor.extract(processed_sexp)
      next if extracted_source.source.empty?

      parsed_ruby = parse_ruby(extracted_source.source)
      next unless parsed_ruby

      report_instance_variables(parsed_ruby, extracted_source.source_map)
    end

    private

    def report_instance_variables(parsed_ruby, source_map)
      parsed_ruby.each_node do |node|
        next unless node.ivar_type?

        # source_map values are SourceLocation objects (not bare line numbers).
        # Adjust by the ivar's column within the extracted Ruby line so the lint
        # points at the exact character in the original Slim file.
        location = source_map[node.loc.line]
        next unless location

        adjusted = location.adjust(column: node.loc.column)
        sexp = Sexp.new(:dummy,
          start: [adjusted.start_line, adjusted.start_column],
          finish: [adjusted.start_line, adjusted.start_column + node.source.length])

        report_lint(sexp,
          "Avoid instance variables in the configured " \
          "view templates (found `#{node.source}`)")
      end
    end
  end
end
