# frozen_string_literal: true

module Frai
  # Base class for all Frai tasks.
  #
  # Execution order:
  #   1. Validate params (if declared)
  #   2. Check structure (all declared files exist)
  #   3. Render directives (scripts run lazily inside renderer)
  #   4. Call LLM via configured adapter
  #   5. Return response
  #
  # @example Minimal task
  #   class AnalyzeItemTask < Frai::Task
  #   end
  #   AnalyzeItemTask.call("some text")
  #
  # @example With params, constants, and sub-directives
  #   class SumNumbersTask < Frai::Task
  #     const :high_value_threshold, 10
  #
  #     directive :main do
  #       params do
  #         required :input_numbers, String
  #       end
  #       directive :sum do
  #         script :parse_numbers do
  #           input   String
  #           returns parsed_numbers: [Integer]
  #         end
  #       end
  #     end
  #   end
  class Task
    class << self
      # Returns the snake_case name derived from the class name.
      # e.g. SumNumbersTask => "sum_numbers"
      #
      # @return [String]
      def task_name
        name.gsub("Task", "")
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      # DSL: declares a constant available as @name in all directives.
      #
      # @param name [Symbol]
      # @param value [Object]
      def const(name, value)
        @_constants       ||= {}
        @_constants[name] = value
      end

      # @return [Hash]
      def _constants
        @_constants || {}
      end

      # DSL: declares the main directive and its structure.
      #
      # @param name [Symbol] directive name (default: :main)
      # @yield [DirectiveDeclaration]
      def directive(name = :main, &block)
        decl = DirectiveDeclaration.new(name)
        decl.instance_eval(&block) if block_given?
        @_directive_declaration = decl
      end

      # @return [Frai::DirectiveDeclaration, nil]
      def _directive_declaration
        @_directive_declaration
      end

      # @param input [Hash, String, nil]
      # @return [Object]
      def call(input = nil)
        new.call(input)
      end

      # Checks structure once per class per process. Subsequent calls are no-ops.
      def ensure_structure_checked!
        return if @_structure_checked
        StructureChecker.new(self).check!
        @_structure_checked = true
      end

      # Resets structure check cache (useful in tests or after file changes).
      def reset_structure_check!
        @_structure_checked = false
      end
    end

    # Executes the full task pipeline.
    #
    # @param input [Hash, String, nil]
    # @return [String] LLM response
    def call(input = nil)
      decl = self.class._directive_declaration

      input = validate_params!(decl, input)
      self.class.ensure_structure_checked!

      script_runner = ScriptRunner.new(self.class.task_name, Frai.configuration.project_root)
      renderer      = DirectiveRenderer.new(
        self.class.task_name,
        Frai.configuration.project_root,
        script_runner,
        self.class._constants
      )

      prompt = renderer.render(decl, input)
      adapter.complete(prompt)
    end

    private

    def validate_params!(decl, input)
      return input unless decl&.params_declaration

      unless input.is_a?(Hash)
        raise Frai::InvalidParam,
          "#{self.class} declares params — input must be a Hash, got #{input.class}"
      end

      decl.params_declaration.validate!(input, self.class)
    end

    def adapter
      adapter_name = Frai.configuration.adapter
      raise Frai::AdapterNotConfigured,
        "No adapter configured. Set config.adapter in config/frai.rb" unless adapter_name

      case adapter_name
      when :null      then Frai::Adapters::Null.new
      when :anthropic then load_adapter("anthropic", "Frai::Adapters::Anthropic")
      when :openai    then load_adapter("openai",    "Frai::Adapters::OpenAI")
      when :ollama    then load_adapter("ollama",    "Frai::Adapters::Ollama")
      else raise Frai::AdapterNotConfigured, "Unknown adapter: #{adapter_name}"
      end
    end

    def load_adapter(file, class_name)
      require_relative "adapters/#{file}"
      Object.const_get(class_name).new
    rescue LoadError
      raise Frai::AdapterNotFound,
        "Adapter '#{file}' not found. Make sure the adapter file exists."
    end
  end
end
