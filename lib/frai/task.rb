module Frai
  # Base class for all Frai tasks.
  #
  # Execution order:
  #   1. Validate params (if declared)
  #   2. Check structure (all declared files exist)
  #   3. Render directives (ERB templates)
  #   4. Run scripts (memoized, results available in directives)
  #   5. Call LLM via configured adapter
  #   6. Return response
  #
  # @example Minimal task
  #   class AnalyzeItemTask < Frai::Task
  #   end
  #   AnalyzeItemTask.call("some text")
  #
  # @example With explicit contract
  #   class AnalyzeItemTask < Frai::Task
  #     directive :main do
  #       params do
  #         required :name,     String
  #         required :category, String
  #         optional :lang,     String, default: "en"
  #       end
  #       uses :system
  #       runs :fetch_data
  #     end
  #   end
  #   AnalyzeItemTask.call(name: "iPhone 15", category: "phones")
  class Task
    class << self
      # Returns the snake_case name derived from the class name.
      # Used to locate task files on disk.
      # e.g. AnalyzeItemTask => "analyze_item"
      #
      # @return [String]
      def task_name
        name.gsub("Task", "")
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      # DSL: declares the entry point directive and its dependencies.
      #
      # @param name [Symbol] directive name (default: :main)
      # @yield [DirectiveDeclaration] block for declaring dependencies
      def directive(name = :main, &block)
        decl = DirectiveDeclaration.new(name)
        decl.instance_eval(&block) if block_given?
        @_directive_declaration = decl
      end

      # DSL: declares a reusable dependency block.
      #
      # @param name [Symbol] scheme name
      # @yield [DirectiveDeclaration] block for declaring dependencies
      def scheme(name, &block)
        @_schemes ||= {}
        decl = DirectiveDeclaration.new(name)
        decl.instance_eval(&block) if block_given?
        @_schemes[name] = decl
      end

      # @return [Frai::DirectiveDeclaration, nil]
      def _directive_declaration
        @_directive_declaration
      end

      # @return [Hash, nil]
      def _schemes
        @_schemes
      end

      # Instantiates and calls the task.
      #
      # @param input [Hash, String, nil]
      # @return [Object]
      def call(input = nil)
        new.call(input)
      end
    end

    # Executes the full task pipeline.
    #
    # @param input [Hash, String, nil]
    # @return [String] LLM response
    def call(input = nil)
      decl = self.class._directive_declaration

      # 1. Validate params if declared
      input = validate_params!(decl, input)

      # 2. Check that all declared files exist
      StructureChecker.new(self.class).check!

      # 3 & 4. Render directives (scripts are run inside renderer, memoized)
      script_runner = ScriptRunner.new(
        self.class.task_name,
        Frai.configuration.project_root
      )

      renderer = DirectiveRenderer.new(
        self.class.task_name,
        Frai.configuration.project_root,
        script_runner
      )

      prompt = renderer.render(decl, input)

      # 5. Call LLM
      adapter.complete(prompt)
    end

    private

    # Validates input against declared params, applies defaults.
    # If no params declared, returns input unchanged.
    def validate_params!(decl, input)
      return input unless decl&.params_declaration

      unless input.is_a?(Hash)
        raise Frai::InvalidParam,
          "#{self.class} declares params — input must be a Hash, got #{input.class}"
      end

      decl.params_declaration.validate!(input, self.class)
    end

    # Returns the configured LLM adapter instance.
    def adapter
      adapter_name = Frai.configuration.adapter

      raise Frai::AdapterNotConfigured,
        "No adapter configured. Set config.adapter in config/frai.rb" unless adapter_name

      case adapter_name
      when :null      then Frai::Adapters::Null.new
      when :anthropic then load_adapter("anthropic", "Frai::Adapters::Anthropic")
      when :openai    then load_adapter("openai",    "Frai::Adapters::OpenAI")
      when :ollama    then load_adapter("ollama",    "Frai::Adapters::Ollama")
      else
        raise Frai::AdapterNotConfigured, "Unknown adapter: #{adapter_name}"
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
