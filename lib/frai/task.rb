# frozen_string_literal: true

module Frai
  # Base class for all Frai tasks.
  #
  # Define the task contract directly in Ruby:
  #
  #   class CodeReviewTask < BaseTask
  #     schema do
  #       mcp :jira
  #       mcp :gitlab
  #
  #       param :task_id,  type: String, required: true
  #       param :language, type: String, default: "english"
  #
  #       use :code_style_guides do
  #         use :naming_rules
  #         use :formatting_rules
  #       end
  #
  #       run :analyze_diff do
  #         input   String
  #         returns do
  #           metrics String
  #         end
  #       end
  #     end
  #   end
  #
  #   CodeReviewTask.call(task_id: "PDB-111")
  class Task
    class SchemaBuilder
      attr_reader :mcps, :constants, :llm_enabled

      def initialize(task_name)
        @task_name   = task_name
        @mcps        = []
        @constants   = {}
        @params      = ParamsDeclaration.new
        @runs        = []
        @uses        = []
        @llm_enabled = true
      end

      # Declare whether this task calls the LLM.
      # Default is true. Set `llm false` to return the rendered prompt only.
      def llm(value)
        @llm_enabled = value
      end

      def mcp(name)
        @mcps << name.to_sym
      end

      def const(name, value)
        @constants[name.to_sym] = value
      end

      def param(name, positional_type = nil, type: nil, required: true, default: nil)
        actual_type   = positional_type || type || String
        resolved_type = resolve_type(actual_type)

        if required && default.nil?
          @params.required(name.to_sym, resolved_type)
        else
          @params.optional(name.to_sym, resolved_type, default: default)
        end
      end

      def use(name, &block)
        child = self.class.new(@task_name)
        child.instance_eval(&block) if block_given?
        @uses << [name.to_sym, child]
      end

      def run(name, input: nil, returns: nil, &block)
        @runs << [name.to_sym, input, returns, block]
      end

      def build_directive(name = :main)
        decl = DirectiveDeclaration.new(name)
        apply_to(decl)
        decl
      end

      def apply_to(decl)
        if @params.required_params.any? || @params.optional_params.any?
          params_snapshot = @params
          decl.params do
            params_snapshot.required_params.each do |param_name, type|
              required(param_name, type)
            end

            params_snapshot.optional_params.each do |param_name, opts|
              optional(param_name, opts[:type], default: opts[:default])
            end
          end
        end

        @uses.each do |child_name, child_builder|
          decl.use(child_name) do
            child_builder.apply_to(self)
          end
        end

        @runs.each do |script_name, input_type, returns_schema, script_block|
          decl.run(script_name, type_resolver: method(:resolve_type)) do
            if script_block
              instance_eval(&script_block)
            end

            input(input_type) if input_type && self.input_type.nil?
            returns(returns_schema) if returns_schema && self.returns_schema.empty?
          end
        end
      end

      private


      def resolve_type(value)
        case value
        when nil
          nil
        when Array
          value.map { |item| resolve_type(item) }
        when Hash
          value.each_with_object({}) do |(key, nested), hash|
            hash[key.to_sym] = resolve_type(nested)
          end
        when String, Symbol
          Object.const_get(value.to_s)
        else
          value
        end
      rescue NameError
        raise Frai::Error, "Unknown type '#{value}' in schema for #{@task_name}"
      end
    end

    class << self
      # Define the task schema directly in the task class.
      def schema(&block)
        builder = SchemaBuilder.new(task_name)
        builder.instance_eval(&block)

        @_mcps                  = builder.mcps
        @_constants             = builder.constants
        @_llm_enabled           = builder.llm_enabled
        @_directive_declaration = builder.build_directive(:main)
      end

      # Returns the snake_case name derived from the class name.
      # e.g. CodeReviewTask => "code_review"
      #
      # @return [String]
      def task_name
        name.gsub("Task", "")
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      # @return [Array<Symbol>]
      def _mcps
        @_mcps ||= []
      end

      # @return [Hash]
      def _constants
        @_constants ||= {}
      end

      # @return [Boolean]
      def _llm_enabled
        @_llm_enabled.nil? ? true : @_llm_enabled
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

      # Checks structure once per project_root. Subsequent calls are no-ops.
      def ensure_structure_checked!
        return if @_structure_checked_for == Frai.configuration.project_root
        StructureChecker.new(self).check!
        @_structure_checked_for = Frai.configuration.project_root
      end

      # Resets structure check cache (useful in tests or after file changes).
      def reset_structure_check!
        @_structure_checked_for = nil
      end

      # Returns the task directory for this class, e.g. tasks/code_review.
      def task_root
        File.join(Frai.configuration.project_root, "tasks", task_name)
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

      if Frai.configuration.non_production?
        warn "Frai [#{Frai.configuration.env}]: all MCPs skipped, LLM not called, returning rendered prompt."
        mcp_servers = []
      else
        mcp_servers = declared_mcp_servers
        verify_mcp_servers!(mcp_servers)
      end

      prompt = renderer.render(decl, input)

      return prompt unless self.class._llm_enabled

      adapter.complete(prompt, mcp_servers: mcp_servers)
    end

    private

    def declared_mcp_servers
      self.class._mcps.map do |name|
        server = Frai::MCP.find(name)
        raise Frai::Error,
          "MCP :#{name} is declared in #{self.class} but not defined in mcp/#{name}.rb.\n" \
          "Create the file or run `frai setup`." unless server
        server
      end
    end

    def verify_mcp_servers!(servers)
      return if servers.empty?
      return if Frai.configuration.model

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

      input = coerce_string_params(decl.params_declaration, input)
      decl.params_declaration.validate!(input, self.class)
    end

    # The CLI passes all param values as plain strings (e.g. `place_data({...})`
    # becomes the string "{...}"). Coerce those strings into the types declared
    # in the schema (Hash, Array) before strict validation runs.
    def coerce_string_params(params_decl, input)
      required = params_decl.required_params
      optional = params_decl.optional_params.transform_values { |o| o[:type] }
      all_types = required.merge(optional)

      result = input.dup
      all_types.each do |name, type|
        next unless result.key?(name) && result[name].is_a?(String)
        next unless [Hash, Array].include?(type)

        result[name] = coerce_value(result[name], type)
      end
      result
    end

    def coerce_value(str, type)
      # 1) Try strict JSON
      require "json"
      begin
        parsed = JSON.parse(str)
        return parsed if parsed.is_a?(type)
      rescue JSON::ParserError
        # fall through
      end

      # 2) Try YAML (handles additional formats)
      require "yaml"
      begin
        parsed = YAML.safe_load(str)
        return parsed if parsed.is_a?(type)
      rescue StandardError
        # fall through
      end

      # 3) Try Ruby literal (handles symbol keys, single quotes from CLI)
      begin
        parsed = eval(str) # rubocop:disable Security/Eval
        return parsed if parsed.is_a?(type)
      rescue StandardError
        # fall through
      end

      str
    end

    def adapter
      return Frai::Adapters::Null.new if Frai.configuration.non_production?

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

# Project-generated task files use `BaseTask` as the conventional superclass.
class BaseTask < Frai::Task; end unless defined?(::BaseTask)

