# frozen_string_literal: true

module Frai
  # Base class for all Frai tasks.
  #
  # Define the task contract directly in Ruby:
  #
  #   module AnalyzeItem
  #     class Task < BaseTask
  #       schema do
  #         mcp :database
  #
  #         param :query,    type: String, required: true
  #         param :language, type: String, default: "english"
  #
  #         directive :task do
  #           use :guidelines
  #           run :fetch_context do
  #             input   type: String
  #             returns :context, type: String
  #           end
  #         end
  #
  #         output :text
  #       end
  #     end
  #   end
  #
  #   AnalyzeItem::Task.call(query: "hello world")
  class Task
    # Returned by Task.run — bundles the primary output with script and prompt metadata.
    # output         — the normal return value (same as Task.call)
    # script_results — Hash of actual script outputs, keyed by return key
    # prompt_results — Hash with :prompt (rendered text) + symbolic keys mirroring script_results
    TaskResult = Struct.new(:output, :script_results, :prompt_results, keyword_init: true)

    class SchemaBuilder
      attr_reader :mcps, :constants, :llm_enabled, :output_kind, :output_schema, :output_validator,
                  :output_validate_method, :output_retries, :output_strict

      def initialize(task_name)
        @task_name         = task_name
        @mcps              = []
        @constants         = {}
        @params            = ParamsDeclaration.new
        @runs              = []
        @uses              = []
        @llm_enabled       = true
        @output_kind       = nil
        @output_schema           = nil
        @output_validator        = nil
        @output_validate_method  = nil
        @output_retries          = nil
        @output_strict     = true
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

      def param(name, positional_type = nil, type: nil, required: true, default: nil, validate: nil, &block)
        actual_type   = positional_type || type || String
        resolved_type = resolve_type(actual_type)

        raise ArgumentError,
          "param :#{name} — cannot use both block and validate: together" if block_given? && validate

        schema = validate

        if block_given?
          unless resolved_type == Hash
            raise ArgumentError,
              "param :#{name} — key schema block is only allowed for type: Hash, got #{resolved_type}"
          end
          require "dry/schema"
          schema = Dry::Schema.define(&block)
        elsif resolved_type == Hash && validate.nil?
          raise ArgumentError,
            "param :#{name} has type: Hash — declare its schema:\n" \
            "  param :#{name}, type: Hash do\n" \
            "    required(:key_name).filled(:string)\n" \
            "  end\n" \
            "Or pass a dry-schema contract:\n" \
            "  param :#{name}, type: Hash, validate: MySchema"
        end

        if required && default.nil?
          @params.required(name.to_sym, resolved_type, schema: schema)
        else
          @params.optional(name.to_sym, resolved_type, default: default, schema: schema)
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

      # Declares the entry-point directive for this task.
      # The block contains `use` and `run` declarations — the same DSL as the
      # top-level schema, but now explicitly named and scoped to one directive file.
      #
      # @example
      #   directive :task do
      #     use :guidelines
      #     run :fetch_diff do
      #       input type: String
      #       returns :diff, type: String
      #     end
      #   end
      def directive(name, &block)
        raise Frai::Error, "directive :#{name} already declared for #{@task_name}" if @directive_name

        @directive_name = name.to_sym
        instance_eval(&block) if block_given?
      end

      # Declare task output contract — required for every task.
      #
      # @param target [Class, :text] RubyLLM::Schema subclass for structured Hash, or `:text` for String
      # @param retries [Integer] how many times to re-ask the LLM after validation errors
      # @param validate [Symbol, nil] instance method to call as `validate!(output, input)` alternative to block
      # @yield [data, params] optional business-rule validation — runs on the task instance when given
      # @param strict [Boolean] strict JSON parsing — no trailing-comma repair (default: true, schema only)
      def output(target, retries: nil, strict: true, validate: nil, &block)
        if @output_kind
          raise Frai::Error, "output already declared for #{@task_name}"
        end

        if validate && block
          raise Frai::Error, "output accepts validate: or a block, not both"
        end

        @output_retries          = retries
        @output_validator        = block
        @output_validate_method  = validate&.to_sym

        if target == :text
          @output_kind = :text
          return
        end

        if target == Hash
          @output_kind   = :hash
          @output_strict = strict
          return
        end

        require "ruby_llm/schema"

        unless target.is_a?(Class) && target < RubyLLM::Schema
          raise Frai::Error,
            "output requires :text, Hash, or a RubyLLM::Schema class, got #{target.inspect}"
        end

        @output_kind     = :schema
        @output_schema   = target
        @output_strict   = strict
      end

      def validate!
        return if @output_kind

        raise Frai::MissingOutput,
          "#{@task_name} must declare output :text, output Hash, or output YourSchema"
      end

      def build_directive
        decl = DirectiveDeclaration.new(@directive_name || :task)
        apply_to(decl)
        decl
      end

      def apply_to(decl)
        if @params.required_params.any? || @params.optional_params.any?
          params_snapshot = @params
          decl.params do
            params_snapshot.required_params.each do |param_name, type|
              required(param_name, type, schema: params_snapshot.param_schemas[param_name])
            end

            params_snapshot.optional_params.each do |param_name, opts|
              optional(param_name, opts[:type], default: opts[:default], schema: params_snapshot.param_schemas[param_name])
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
        builder.validate!

        @_mcps                  = builder.mcps
        @_constants             = builder.constants
        @_llm_enabled           = builder.llm_enabled
        @_output_kind           = builder.output_kind
        @_output_schema         = builder.output_schema
        @_output_validator       = builder.output_validator
        @_output_validate_method = builder.output_validate_method
        @_output_retries         = builder.output_retries
        @_output_strict         = builder.output_strict
        @_directive_declaration = builder.build_directive
      end

      # Returns the snake_case name derived from the class name or namespace.
      # e.g. AnalyzeItem::Task => "analyze_item"
      #
      # @return [String]
      def task_name
        base_name = if name.end_with?("::Task")
          name.delete_suffix("::Task")
        else
          name.delete_suffix("Task")
        end

        base_name = base_name.gsub("::", "_")

        base_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
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

      # @return [Class, nil]
      def _output_schema
        @_output_schema
      end

      # @return [Proc, nil]
      def _output_validator
        @_output_validator
      end

      # @return [Symbol, nil]
      def _output_validate_method
        @_output_validate_method
      end

      # @return [Integer]
      def _output_retries
        @_output_retries.nil? ? Frai.configuration.default_retries.to_i : @_output_retries
      end

      def _output_strict
        @_output_strict.nil? ? true : @_output_strict
      end

      # @return [Symbol, nil] :schema, :text, or nil when llm is disabled
      def _output_kind
        @_output_kind
      end

      # @param input [Hash, String, nil]
      # @return [Object]
      def call(input = nil)
        new.call(input)
      end

      # Executes the task and returns a TaskResult with all three outputs:
      # output, script_results, and prompt_results.
      #
      # Use when you need script or prompt metadata alongside the primary output.
      # Task.call stays unchanged and returns only the primary output.
      #
      # @example
      #   result = PrepareReport::Task.run(language: "en", data: ..., llm_data: ...)
      #   result.output          # => "The dataset shows clear patterns..."
      #   result.script_results  # => { prepared_data: { item_id: "...", ... } }
      #   result.prompt_results  # => { prompt: "You are a data analyst...", prepared_data: :prepared_data }
      #
      # @param input [Hash, String, nil]
      # @return [Frai::Task::TaskResult]
      def run(input = nil)
        instance = new
        output   = instance.call(input)
        TaskResult.new(
          output:         output,
          script_results: instance.script_results,
          prompt_results: instance.prompt_results
        )
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
    # @return [String, Hash]
    #   - rendered prompt when llm false + output :text, or when llm true + non-production
    #   - Hash when output Schema or output Hash
    #   - String when output :text
    def call(input = nil)
      decl = self.class._directive_declaration

      input = validate_params!(decl, input)
      self.class.ensure_structure_checked!

      script_runner = ScriptRunner.new(self.class.task_name, Frai.configuration.project_root)
      renderer      = DirectiveRenderer.new(
        self.class.task_name,
        Frai.configuration.project_root,
        script_runner,
        self.class._constants,
        self.class._directive_declaration
      )

      if Frai.configuration.dry_run?
        # development / test: skip MCPs and LLM — return rendered prompt
        warn "Frai [#{Frai.configuration.env}]: dry run — MCPs skipped, LLM not called."
        mcp_servers = []
      else
        # production: resolve MCP definitions from mcp/*.rb.
        # In cli_mode Frai only renders the prompt — the client runs MCP tools.
        mcp_servers = declared_mcp_servers
      end

      prompt = renderer.render(decl, input)
      @_script_results = script_runner.return_values
      @_prompt_results = { prompt: prompt }.merge(
        @_script_results.keys.each_with_object({}) { |k, h| h[k] = k }
      )

      # llm false: no LLM call; output Hash parses the rendered directive, output :text returns it as-is
      unless self.class._llm_enabled
        return parse_rendered_as_hash(prompt, input) if self.class._output_kind == :hash
        return prompt
      end

    # llm true, dry run / agent tool / CLI mode: return rendered prompt
    # In test, mock the task via allow(...).to receive(:call) if you need a Hash
    return prompt if Frai.configuration.dry_run? || Frai.configuration.inside_agent_tool? || Frai.configuration.cli_mode?

      case self.class._output_kind
      when :schema
        complete_with_json_output(prompt, mcp_servers, input)
      when :hash
        complete_with_hash_output(prompt, mcp_servers, input)
      when :text
        complete_with_text_output(prompt, mcp_servers, input)
      end
    end

    # Returns extracted script return values, keyed by the return key declared in the directive.
    # Available in overridden +call+ after +super+.
    #
    #   % run(:prepare_data, params: :item_id, return: :prepared_data)
    #
    # gives you:
    #
    #   script_results[:prepared_data]  # => { item_id: "...", ... }
    #
    # Returns +{}+ only if the directive template doesn't call any scripts.
    #
    # @example
    #   def call(input)
    #     llm_result = super
    #     [script_results[:prepared_data], llm_result]
    #   end
    #
    # @return [Hash{Symbol => Object}]
    def script_results
      @_script_results || {}
    end

    # Returns the rendered prompt alongside symbolic references to script outputs.
    # Symmetric to script_results: same keys, but values are the key symbols — not data.
    # Use to get the prompt and discover which script outputs are available.
    #
    #   % run(:prepare_data, params: :data, return: :prepared_data)
    #
    # gives you:
    #
    #   prompt_results[:prompt]        # => "You are a review analyst..."
    #   prompt_results[:prepared_data] # => :prepared_data  (symbolic reference)
    #   script_results[:prepared_data] # => { item_id: "...", ... }  (actual data)
    #
    # @return [Hash{Symbol => Object}]
    def prompt_results
      @_prompt_results || {}
    end

    private

    def complete_with_json_output(prompt, mcp_servers, input)
      attempts   = self.class._output_retries + 1
      last_error = nil
      last_raw   = nil

      attempts.times do |index|
        attempt_num    = index + 1
        current_prompt = index.zero? ? prompt : retry_prompt(prompt, last_error)

        last_raw = adapter.complete(
          current_prompt,
          mcp_servers: mcp_servers,
          schema:      self.class._output_schema
        )

        return Frai::JsonResponse.normalize(
          last_raw,
          validate:           output_validation,
          validator_receiver: output_validation ? self : nil,
          context:            input,
          strict:             self.class._output_strict,
          attempt:            attempt_num,
          task_class:         self.class
        )
      rescue Frai::JsonParseError, Frai::ValidationError => e
        last_error = e
        if index == attempts - 1
          raise Frai::OutputRetriesExhaustedError.new(
            e,
            attempts:   attempts,
            task_class: self.class,
            raw:        last_raw
          )
        end
      end
    end

    def complete_with_hash_output(prompt, mcp_servers, input)
      attempts   = self.class._output_retries + 1
      last_error = nil
      last_raw   = nil

      attempts.times do |index|
        attempt_num    = index + 1
        current_prompt = index.zero? ? prompt : retry_prompt(prompt, last_error)

        last_raw = adapter.complete(current_prompt, mcp_servers: mcp_servers)

        return Frai::JsonResponse.normalize(
          last_raw,
          validate:           output_validation,
          validator_receiver: output_validation ? self : nil,
          context:            input,
          strict:             self.class._output_strict,
          attempt:            attempt_num,
          task_class:         self.class
        )
      rescue Frai::JsonParseError, Frai::ValidationError => e
        last_error = e
        if index == attempts - 1
          raise Frai::OutputRetriesExhaustedError.new(
            e,
            attempts:   attempts,
            task_class: self.class,
            raw:        last_raw
          )
        end
      end
    end

    def parse_rendered_as_hash(rendered, input)
      Frai::JsonResponse.normalize(
        rendered,
        validate:           output_validation,
        validator_receiver: output_validation ? self : nil,
        context:            input,
        strict:             self.class._output_strict,
        task_class:         self.class
      )
    rescue Frai::JsonParseError => e
      raise Frai::OutputRetriesExhaustedError.new(
        e, attempts: 1, task_class: self.class, raw: rendered
      )
    end

    RETRY_MESSAGE_LIMIT = 300

    def complete_with_text_output(prompt, mcp_servers, input)
      attempts   = self.class._output_retries + 1
      last_error = nil
      last_raw   = nil

      attempts.times do |index|
        attempt_num    = index + 1
        current_prompt = index.zero? ? prompt : retry_prompt(prompt, last_error, format: :text)

        last_raw = adapter.complete(current_prompt, mcp_servers: mcp_servers)
        text     = last_raw.to_s

        run_output_validator!(text, input, attempt: attempt_num, raw: last_raw)
        return text
      rescue Frai::ValidationError => e
        last_error = e
        if index == attempts - 1
          raise Frai::OutputRetriesExhaustedError.new(
            e,
            attempts:   attempts,
            task_class: self.class,
            raw:        last_raw
          )
        end
      end
    end

    def output_validation
      self.class._output_validate_method || self.class._output_validator
    end

    def run_output_validator!(value, input, attempt:, raw:)
      validate = output_validation
      return unless validate

      Frai::JsonResponse.run_validator!(
        validate,
        value,
        input,
        raw:                raw,
        attempt:            attempt,
        task_class:         self.class,
        validator_receiver: self
      )
    end

    def retry_prompt(original, error, format: :schema)
      message = error.message.to_s.strip
      message = "#{message[0, RETRY_MESSAGE_LIMIT]}…" if message.length > RETRY_MESSAGE_LIMIT
      fix_hint = format == :text ? "valid text matching the requirements" : "valid JSON matching the required schema"

      <<~PROMPT.rstrip
        #{original}

        ---
        Your previous response failed validation: #{message}
        Fix the issues and return #{fix_hint}.
      PROMPT
    end

    def declared_mcp_servers
      self.class._mcps.map do |name|
        server = Frai::MCP.find(name)
        raise Frai::Error,
          "MCP :#{name} is declared in #{self.class} but not defined in mcp/#{name}.rb.\n" \
          "Create mcp/#{name}.rb." unless server
        server
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
      Frai::ParamCoercion.parse_as(str, type)
    end

    def adapter
      return Frai::Adapters::Null.new if Frai.configuration.dry_run?

      model = Frai.configuration.model
      return Frai::Adapters::Null.new unless model

      require_relative "adapters/ruby_llm"
      Frai::Adapters::RubyLlm.new(model)
    rescue LoadError
      raise Frai::Error,
        "ruby_llm gem not found. Add `gem \"ruby_llm\"` to your Gemfile."
    end
  end
end

# Project-generated task files use `BaseTask` as the conventional superclass.
class BaseTask < Frai::Task; end unless defined?(::BaseTask)
