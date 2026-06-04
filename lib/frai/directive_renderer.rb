# frozen_string_literal: true

require "erb"

module Frai
  # Renders directive files (Markdown + ERB) into a final prompt string.
  #
  # ERB helpers available inside directive templates:
  #
  #   directive(:name).with(@param).and_return(:result_ivar)
  #     Renders a sub-directive with the given input.
  #     Extracts @result_ivar from sub-directive context and sets it on parent.
  #     Returns "" (no text output). Use <%= directive(...) %> to output rendered text.
  #
  #   script(:name).with(param).and_return(:result_key)
  #     Runs a script with the given input.
  #     Extracts :result_key from JSON output, exposes as result_key method.
  #     Type is declared in task.rb — no need to repeat here.
  #     Returns "" (no text output).
  #
  #   @variable
  #     Access any input param, constant, or script/directive result.
  #
  # @example sum.md.erb
  #   <% script(:parse_numbers).with(:input_numbers).and_return(:parsed_numbers) %>
  #   <% script(:sum_numbers).with(:parsed_numbers).and_return(:calculated_sum) %>
  #
  # @example main.md.erb
  #   <% directive(:sum).with(:input_numbers).and_return(:calculated_sum) %>
  #   <% if calculated_sum > high_value_threshold %>
  #     <%= directive(:high_value).with(@calculated_sum) %>
  #   <% end %>
  class DirectiveRenderer
    # Handles directive(:name).with(@input).and_return(:ivar) chains.
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
      def initialize(runner, name, ctx)
        @runner = runner
        @name   = name
        @ctx    = ctx
        @input  = nil
        @result = nil
      end

      def with(input)
        @input = input.is_a?(Symbol) ? @ctx.instance_variable_get(:"@#{input}") : input
        self
      end

      # Runs script, extracts :key from JSON output, exposes on context.
      # Type is declared in task.rb and validated there — do not pass it here.
      # Returns "" — no text output.
      def and_return(key, type = nil)
        result = execute!
        value  = result[key]
        validate_type!(value, type, key) if type
        @ctx.instance_variable_set(:"@#{key}", value)
        @ctx.define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        ""
      end

      def to_s
        execute!.to_s
      end

      private

      def execute!
        @result ||= @runner.run(@name, @input)
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
    def initialize(task_name, project_root, script_runner, constants = {})
      @task_name     = task_name.to_s
      @project_root  = project_root
      @script_runner = script_runner
      @constants     = constants
    end

    # Renders the main directive and returns the final prompt string.
    #
    # @param _declaration [DirectiveDeclaration, nil] unused — structure already checked
    # @param input [Hash, String, nil]
    # @return [String] rendered prompt
    def render(_declaration, input)
      path = find_directive!(:main)
      ctx  = build_context(input)
      inject_helpers(ctx)
      render_file(path, ctx)
    end

    private

    def render_sub_directive(name, input)
      path    = find_directive!(name)
      sub_ctx = build_context(input.is_a?(Hash) ? input : { input: input })
      inject_helpers(sub_ctx)
      text = render_file(path, sub_ctx)
      SubDirectiveResult.new(text, sub_ctx)
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

    def inject_helpers(ctx)
      renderer = self
      runner   = @script_runner

      ctx.define_singleton_method(:directive) do |name|
        DirectiveRenderer::DirectiveCall.new(renderer, name, self)
      end

      ctx.define_singleton_method(:script) do |name|
        DirectiveRenderer::ScriptCall.new(runner, name, self)
      end
    end

    def render_file(path, ctx)
      ERB.new(File.read(path), trim_mode: "-").result(ctx.instance_eval { binding })
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
        "Expected: tasks/#{@task_name}/directives/#{name}.md.erb"
    end
  end
end
