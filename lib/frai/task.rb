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
  #       use :sum do
  #         run :parse_numbers do
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

      # DSL: declares an MCP server dependency for this task.
      # In CLI mode — verified against Claude CLI registration.
      # In API mode — connected as tools for the LLM.
      #
      # @param name [Symbol] server name defined in mcp/*.rb
      def mcp(name)
        @_mcps ||= []
        @_mcps << name
      end

      # @return [Array<Symbol>]
      def _mcps
        @_mcps || []
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

      mcp_servers = declared_mcp_servers
      verify_mcp_servers!(mcp_servers)
      prompt = renderer.render(decl, input)
      adapter.complete(prompt, mcp_servers: mcp_servers)
    end

    private

    # Resolves declared MCP names to ServerDefinition objects.
    def declared_mcp_servers
      self.class._mcps.map do |name|
        server = Frai::MCP.find(name)
        raise Frai::Error,
          "MCP :#{name} is declared in #{self.class} but not defined in mcp/#{name}.rb.\n" \
          "Create the file or run `frai setup`." unless server
        server
      end
    end

    # Verifies MCP servers are accessible before calling the LLM.
    # API mode: adapter handles the actual connection check.
    # CLI mode: verifies servers are registered with Claude CLI.
    def verify_mcp_servers!(servers)
      return if servers.empty?
      return if Frai.configuration.model  # API mode — adapter will check

      registered = `claude mcp list 2>/dev/null`
      servers.each do |server|
        next if registered.include?(server.name.to_s)

        raise Frai::Error,
          "MCP :#{server.name} is not registered with Claude CLI.\n" \
          "Run `frai setup` to register it."
      end
    end

    def validate_params!(decl, input)
      return input unless decl&.params_declaration

      unless input.is_a?(Hash)
        raise Frai::InvalidParam,
          "#{self.class} declares params — input must be a Hash, got #{input.class}"
      end

      decl.params_declaration.validate!(input, self.class)
    end

    def adapter
      model = Frai.configuration.model
      return Frai::Adapters::Null.new unless model

      require_relative "adapters/ruby_llm"
      Frai::Adapters::RubyLlm.new(model, Frai.configuration.api_key)
    rescue LoadError
      raise Frai::Error,
        "ruby_llm gem not found. Add `gem \"ruby_llm\"` to your Gemfile."
    end
  end
end
