require "erb"

module Frai
  # Renders directive files (Markdown + ERB) into a final prompt string.
  #
  # ERB helpers available inside directive templates:
  #
  #   receive(:name)
  #     Documents that this directive expects a param. No-op at runtime
  #     (params are already validated), but makes the directive self-documenting.
  #
  #   use(:directive_name, param: value)
  #     Renders a sub-directive and returns a DirectiveResult object.
  #     Use .get(:key) to capture a named return value from the sub-directive.
  #
  #   return_value(:name, value)
  #     Declares what this directive returns to its caller.
  #     Must match the type declared in `returns :name, Type` in task.rb.
  #
  # @example main.md.erb
  #   <% receive :input_numbers %>
  #   You are a math assistant.
  #   <% use(:sum, parsed_numbers: input_numbers).get(:calculated_sum) %>
  #   <%= use(:footer, calculated_sum: calculated_sum) %>
  #   <% return_value :final_response, response %>
  class DirectiveRenderer
    # Wraps the result of rendering a sub-directive.
    # Provides .get(:key) to capture named return values.
    class DirectiveResult
      attr_reader :rendered_text, :return_values

      def initialize(rendered_text, return_values)
        @rendered_text  = rendered_text
        @return_values  = return_values  # { name => value }
      end

      def to_s
        @rendered_text
      end

      # Captures a return value from the sub-directive and makes it available
      # as an instance variable in the parent ERB context.
      # Called via use(:sum, ...).get(:calculated_sum)
      #
      # @param key [Symbol]
      # @return [self] for chaining
      def get(key, context: nil)
        value = @return_values[key]
        # Store in context if provided (set from ERB binding)
        if context
          context.instance_variable_set(:"@#{key}", value)
          context.define_singleton_method(key) { instance_variable_get(:"@#{key}") }
        end
        self
      end
    end

    # @param task_name [String] snake_case task name
    # @param project_root [String] absolute path to project root
    # @param script_runner [Frai::ScriptRunner]
    def initialize(task_name, project_root, script_runner)
      @task_name     = task_name.to_s
      @project_root  = project_root
      @script_runner = script_runner
    end

    # Renders the full prompt for a task.
    #
    # @param declaration [DirectiveDeclaration, nil]
    # @param input [Hash, String, nil]
    # @return [String] final rendered prompt
    def render(declaration, input)
      ctx = build_context(input, {}, {})
      if declaration
        result = render_declaration(declaration, ctx)
        result.rendered_text
      else
        render_file(find_directive!(:main), ctx)
      end
    end

    private

    # Renders a directive declaration and returns a DirectiveResult.
    def render_declaration(decl, parent_ctx)
      # Build local context from params passed by parent
      params = extract_params(decl, parent_ctx)

      # Run all declared scripts (memoized), pass only declared `with:` params
      script_results = run_scripts(decl, params)

      # Build ERB context with params + script results + helpers
      ctx = build_context(params, script_results, {})
      inject_helpers(ctx, decl, params, script_results)

      # Render the directive file
      path = find_directive!(decl.name)
      rendered = render_file(path, ctx)

      # Validate and collect return value
      return_values = collect_return_values(decl, ctx)

      DirectiveResult.new(rendered, return_values)
    end

    # Runs all scripts declared in this directive (not recursive — sub-directives handle their own).
    def run_scripts(decl, params)
      results = {}
      decl.script_declarations.each do |script_decl|
        result = @script_runner.run(script_decl, params)
        results[script_decl.name] = result
      end
      results
    end

    # Extracts params for this directive from the parent context.
    # If directive has params_declaration, only those keys are used.
    def extract_params(decl, parent_ctx)
      return {} unless decl.params_declaration
      decl.params_declaration.required_params.keys
          .concat(decl.params_declaration.optional_params.keys)
          .each_with_object({}) do |key, h|
        if parent_ctx.instance_variable_defined?(:"@#{key}")
          h[key] = parent_ctx.instance_variable_get(:"@#{key}")
        end
      end
    end

    # Injects ERB helper methods into the context object.
    def inject_helpers(ctx, decl, params, script_results)
      renderer = self

      # receive(:name) — self-documenting, no-op at runtime
      ctx.define_singleton_method(:receive) { |_name| nil }

      # return_value(:name, value) — stores directive's return value
      ctx.instance_variable_set(:@_return_values, {})
      ctx.define_singleton_method(:return_value) do |name, value|
        @_return_values[name] = value
      end

      # use(:directive_name, params) — renders sub-directive
      ctx.define_singleton_method(:use) do |directive_name, **sub_params|
        sub_decl = decl.sub_declarations[directive_name]
        raise Frai::UndeclaredDependency,
          "directive '#{directive_name}' is not declared in the directive block. " \
          "Add 'uses :#{directive_name}' to your task." unless sub_decl

        # Build sub-context with passed params
        sub_ctx = renderer.send(:build_context, sub_params, {}, {})
        renderer.send(:inject_helpers, sub_ctx, sub_decl, sub_params, {})

        result = renderer.send(:render_declaration_with_ctx, sub_decl, sub_ctx)

        # Wrap in DirectiveResult with context for .get()
        DirectiveResult.new(result.rendered_text, result.return_values).tap do |dr|
          dr.instance_variable_set(:@_parent_ctx, ctx)

          # Override get to inject into parent context
          dr.define_singleton_method(:get) do |key|
            value = instance_variable_get(:@return_values)[key]
            @_parent_ctx.instance_variable_set(:"@#{key}", value)
            @_parent_ctx.define_singleton_method(key) { instance_variable_get(:"@#{key}") }
            self
          end
        end
      end
    end

    def render_declaration_with_ctx(decl, ctx)
      # Collect all available params from context
      params = {}
      ctx.instance_variables.each do |ivar|
        key = ivar.to_s.delete("@").to_sym
        next if key.to_s.start_with?("_")
        params[key] = ctx.instance_variable_get(ivar)
      end

      decl.script_declarations.each do |script_decl|
        # Merge script results into available params so subsequent scripts can use them
        result = @script_runner.run(script_decl, params.merge(
          decl.script_declarations
              .select { |sd| @script_runner.result(sd.name) }
              .each_with_object({}) { |sd, h| h.merge!(@script_runner.result(sd.name) || {}) }
        ))
        ctx.instance_variable_set(:"@#{script_decl.name}", result)
        ctx.define_singleton_method(script_decl.name) { instance_variable_get(:"@#{script_decl.name}") }
        # Also make individual result keys available as top-level variables
        result.each do |key, value|
          params[key] = value
          ctx.instance_variable_set(:"@#{key}", value)
          ctx.define_singleton_method(key) { instance_variable_get(:"@#{key}") } unless ctx.respond_to?(key)
        end
      end

      path     = find_directive!(decl.name)
      rendered = render_file(path, ctx)
      return_values = collect_return_values(decl, ctx)

      DirectiveResult.new(rendered, return_values)
    end

    # Collects return_value declarations from rendered context.
    def collect_return_values(decl, ctx)
      return_values = ctx.instance_variable_get(:@_return_values) || {}

      if decl.returns_declaration && !return_values.key?(decl.returns_declaration.name)
        raise Frai::InvalidDirectiveOutput,
          "directive '#{decl.name}' declares 'returns :#{decl.returns_declaration.name}' " \
          "but return_value was never called in the template."
      end

      if decl.returns_declaration
        name  = decl.returns_declaration.name
        type  = decl.returns_declaration.type
        value = return_values[name]
        unless value.is_a?(type)
          raise Frai::InvalidDirectiveOutput,
            "directive '#{decl.name}' returns :#{name} expected #{type}, got #{value.class}"
        end
      end

      return_values
    end

    # Builds an ERB context object with all variables available as methods.
    def build_context(input, script_results, extra)
      ctx = Object.new

      # Add input (hash or raw value)
      normalized = input.is_a?(Hash) ? input : { input: input }
      normalized.merge(extra).each do |key, value|
        ctx.instance_variable_set(:"@#{key}", value)
        ctx.define_singleton_method(key) { instance_variable_get(:"@#{key}") }
      end

      # Add raw input accessor
      ctx.instance_variable_set(:@input, input)
      ctx.define_singleton_method(:input) { @input }

      # Add script results
      script_results.each do |name, result|
        ctx.instance_variable_set(:"@#{name}", result)
        ctx.define_singleton_method(name) { instance_variable_get(:"@#{name}") }
      end

      ctx
    end

    # Renders an ERB file with the given context object.
    def render_file(path, ctx)
      template = File.read(path)
      ERB.new(template, trim_mode: "-").result(ctx.instance_eval { binding })
    end

    # Finds a directive file: local first, then global.
    def find_directive!(name)
      local  = File.join(@project_root, "tasks", @task_name, "directives", "#{name}.md.erb")
      global = File.join(@project_root, "directives", "#{name}.md.erb")

      if File.exist?(local)
        local
      elsif File.exist?(global)
        global
      else
        raise Frai::MissingDirective,
          "directive '#{name}' not found.\n" \
          "Expected: tasks/#{@task_name}/directives/#{name}.md.erb\n" \
          "      or: directives/#{name}.md.erb"
      end
    end
  end
end
