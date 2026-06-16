# frozen_string_literal: true

module Frai
  # Collects script return keys declared in a task schema and directive templates.
  module TaskReturnKeys
    ERB_RETURN_PATTERN = /
      return:\s*
      (?::([a-z_][a-z0-9_]*)|"([^"]+)"|'([^']+)')
    /ix

    class << self
      # @param task_class [Class<Frai::Task>]
      # @param project_root [String]
      # @return [Array<Symbol>]
      def collect(task_class, project_root: Frai.configuration.project_root)
        keys = schema_return_keys(task_class)
        keys.concat(erb_return_keys(task_class, project_root))
        keys.map(&:to_sym).uniq
      end

      private

      def schema_return_keys(task_class)
        decl = task_class._directive_declaration
        return [] unless decl

        decl.all_script_declarations.each_value.flat_map do |script_decl|
          script_decl.returns_schema.keys
        end
      end

      def erb_return_keys(task_class, project_root)
        dir = File.join(project_root, "tasks", task_class.task_name, "directives")
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "*.{md.erb,erb}")).flat_map do |path|
          File.read(path).scan(ERB_RETURN_PATTERN).filter_map do |a, b, c|
            (a || b || c)&.to_sym
          end
        end
      end
    end
  end
end
