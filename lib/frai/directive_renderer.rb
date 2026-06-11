# frozen_string_literal: true

require "erb"

module Frai
  # Renders directive files (Markdown + ERB) into a final prompt string.
  #
  # Helpers available inside directive templates:
  #
  #   % run("script_name", params: :input_param, return: :result)
  #   % run("script_name", params: [:param1, :param2], return: :result)
  #   % use("sub_directive", params: :input_param, return: :result)
  #   <%= use("sub_directive") %>
  #   <%= use("sub_directive", params: :input_param) %>
  #
  # % at line start — no closing tag needed (ERB shorthand).
  # <%= %> for inline output.
  #
  # Conditional logic:
  #
  #   % if calculated_sum > max_items
  #     <%= use("high_value") %>
  #   % end
  #
  # Variables (params, constants, script/directive results):
  #
  #   <%= query %>   <%= context %>   <%= max_items %>
  #
  class DirectiveRenderer
    # Handles use(:name).with(:input).and_return(:ivar) chains.
    class DirectiveCall
      def initialize(renderer, name, parent_ctx)
        @renderer   = renderer
        @name       = name
        @parent_ctx = parent_ctx
        @input      = nil
        @result     = nil
      end

      def with(input)
        @input = resolve(input)
        self
      end

      # Renders sub-directive, extracts ivar_name from its context, exposes on parent.
      # Returns "" — no text output.
      def and_return(ivar_name)
        result = execute!
        value  = result.ctx.instance_variable_get(:"@#{ivar_name}")
        @renderer.send(:expose, @parent_ctx, ivar_name, value)
        ""
      end

      def to_s
        execute!.text
      end

      private

      def execute!
        @result ||= @renderer.send(:render_sub_directive, @name, @input)
      end

      # Resolves input for sub-directive:
      #   :symbol       → { symbol: ctx_value }  (name is both key and lookup)
      #   { k: :sym }   → { k: ctx_value }       (resolve symbol values)
      #   other         → passed as-is
      def resolve(input)
        case input
        when Symbol
          { input => @parent_ctx.instance_variable_get(:"@#{input}") }
        when Hash
          input.transform_values { |v| v.is_a?(Symbol) ? @parent_ctx.instance_variable_get(:"@#{v}") : v }
        else
          input
        end
      end
    end

    # Handles script(:name).with(@input).and_return(:key, Type) chains.
    class ScriptCall
      def initialize(runner, name, ctx, decl = nil)
        @runner = runner
        @name   = name
        @ctx    = ctx
        @decl   = decl
        @input  = nil
        @result = nil
      end

      def with(input)
        @input = input.is_a?(Symbol) ? @ctx.instance_variable_get(:"@#{input}") : input
        self
      end

      # Runs script, extracts :key from JSON output, validates against dry-schema if declared.
      # Returns "" — no text output.
      def and_return(key, type = nil)
        result = execute!
        value  = result[key]
        validate_type!(value, type, key) if type
        validate_output!(key, value)
        @ctx.instance_variable_set(:"@#{key}", value)
        @ctx.define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        @runner.store_return(key, value)
        ""
      end

      def to_s
        execute!.to_s
      end

      private

      def execute!
        return @result if @result
        validate_input!
        @result = @runner.run(@name, @input)
      end

      def validate_input!
        schema = @decl&.input_schema
        return unless schema&.respond_to?(:call)

        result = schema.call(@input.is_a?(Hash) ? @input : { input: @input })
        return if result.success?

        raise Frai::InvalidParam,
          "Script '#{@name}' input validation failed: #{result.errors.to_h}"
      end

      def validate_output!(key, value)
        schema = @decl&.returns_dry_schemas&.[](key)
        return unless schema&.respond_to?(:call)

        result = schema.call(value.is_a?(Hash) ? value : { value: value })
        return if result.success?

        raise Frai::InvalidScriptOutput,
          "Script '#{@name}' output :#{key} validation failed: #{result.errors.to_h}"
      end

      def validate_type!(value, type, key)
        return if value.is_a?(type)
        raise Frai::InvalidScriptOutput,
          "Script '#{@name}' returned :#{key} as #{value.class}, expected #{type}"
      end
    end

    SubDirectiveResult = Struct.new(:text, :ctx)

    # @param task_name [String] snake_case task name
    # @param project_root [String] absolute path to project root
    # @param script_runner [Frai::ScriptRunner]
    # @param constants [Hash] task-level constants — available as @name in all directives
    # @param declaration [DirectiveDeclaration, nil] used for input/output schema validation
    def initialize(task_name, project_root, script_runner, constants = {}, declaration = nil)
      @task_name     = task_name.to_s
      @project_root  = project_root
      @script_runner = script_runner
      @constants     = constants
      @declaration   = declaration
    end

    # Renders the main directive and returns the final prompt string.
    #
    # @param _declaration [DirectiveDeclaration, nil] unused — structure already checked
    # @param input [Hash, String, nil]
    # @return [String] rendered prompt
    def render(_declaration, input)
      path = find_directive!(@declaration&.name || :task)
      ctx  = build_context(input)
      inject_helpers(ctx)
      strip_desc_tags(render_file(path, ctx))
    end

    private

    def render_sub_directive(name, input)
      path    = find_directive!(name)
      sub_ctx = build_context(input.is_a?(Hash) ? input : { input: input })
      inject_helpers(sub_ctx)
      text = strip_desc_tags(render_file(path, sub_ctx))
      SubDirectiveResult.new(text, sub_ctx)
    end

    def strip_desc_tags(text)
      text.gsub(%r{<desc>.*?</desc>\n?}m, "").lstrip
    end

    def build_context(input)
      ctx = Object.new

      @constants.each do |name, value|
        expose(ctx, name, value)
      end

      normalized = input.is_a?(Hash) ? input : { input: input }
      normalized.each do |key, value|
        expose(ctx, key, value)
      end

      ctx
    end

    # Sets @name and defines a memoized reader method — like attr_reader.
    def expose(ctx, name, value)
      ctx.instance_variable_set(:"@#{name}", value)
      ctx.define_singleton_method(name) { instance_variable_get(:"@#{name}") }
    end

    # Applies opts to a DirectiveCall or ScriptCall, returning the configured call.
    # Extracted to avoid duplicating the same case/when block for both `use` and `run`.
    def apply_call_opts(call, opts, ctx)
      case opts
      when nil    then call
      when Symbol then call.with(opts)
      when Hash
        if opts.key?(:params) || opts.key?(:return)
          input = DirectiveRenderer.resolve_params(opts[:params], ctx)
          call  = call.with(input) if input
          opts[:return] ? call.and_return(opts[:return]) : call
        else
          input_spec, output_key = opts.first
          input = input_spec.is_a?(Hash) \
            ? input_spec.transform_values { |v| v.is_a?(Symbol) ? ctx.instance_variable_get(:"@#{v}") : v }
            : input_spec
          call.with(input).and_return(output_key)
        end
      end
    end

    def inject_helpers(ctx)
      renderer    = self
      runner      = @script_runner
      declaration = @declaration

      ctx.define_singleton_method(:use) do |name, opts = nil|
        if declaration && !declaration.all_directive_names.include?(name.to_sym)
          raise Frai::UndeclaredDirective, "Cannot use(:#{name}) because it is not declared in the task schema via `use :#{name}`"
        end

        call = DirectiveRenderer::DirectiveCall.new(renderer, name.to_sym, self)
        renderer.send(:apply_call_opts, call, opts, self)
      end

      ctx.define_singleton_method(:run) do |name, opts = nil|
        if declaration && !declaration.all_script_names.include?(name.to_sym)
          raise Frai::UndeclaredScript, "Cannot run(:#{name}) because it is not declared in the task schema via `run :#{name}`"
        end

        script_decl = declaration&.all_script_declarations&.[](name.to_sym)
        call = DirectiveRenderer::ScriptCall.new(runner, name.to_sym, self, script_decl)
        renderer.send(:apply_call_opts, call, opts, self)
      end
    end

    def self.resolve_params(input_spec, ctx)
      return input_spec unless input_spec.is_a?(Array)

      input_spec.each_with_object({}) { |k, h| h[k] = ctx.instance_variable_get(:"@#{k}") }
    end

    def render_file(path, ctx)
      ERB.new(File.read(path), trim_mode: "%-").result(ctx.instance_eval { binding })
    end

    def find_directive!(name)
      candidates = [
        File.join(@project_root, "tasks", @task_name, "directives", "#{name}.md.erb"),
        File.join(@project_root, "tasks", @task_name, "directives", "#{name}.erb"),
        File.join(@project_root, "directives", "#{name}.md.erb")
      ]

      path = candidates.find { |p| File.exist?(p) }
      return path if path

      raise Frai::MissingDirective,
        "Directive '#{name}' not found.\n" \
        "Expected: tasks/#{@task_name}/directives/#{name}.md.erb\n" \
        "      or: directives/#{name}.md.erb"
    end
  end
end
