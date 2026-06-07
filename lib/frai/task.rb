# frozen_string_literal: true

require "yaml"

module Frai
  # Base class for all Frai tasks.
  #
  # The task contract lives entirely in tasks/<name>/task.yml.
  # The Ruby class is a thin entrypoint only — it provides TaskNameTask.call(params).
  # All params, directives, mcp and constants are declared in YAML.
  #
  # Calling convention:
  #   TaskNameTask.call("plain string input")
  #   TaskNameTask.call(param_name: value, ...)   # when params declared in task.yml
  #
  # Execution order:
  #   1. Load and hydrate task.yml
  #   2. Validate params against task.yml declarations
  #   3. Check structure (all declared files exist)
  #   4. Render directives (scripts run lazily inside renderer)
  #   5. Call LLM via configured adapter
  #   6. Return response
  #
  # @example
  #   class AnalyzeItemTask < Frai::Task
  #   end
  #
  #   AnalyzeItemTask.call("some text")
  #   AnalyzeItemTask.call(name: "item", category: "things")
  class Task
    class << self
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
        load_yaml_definition!
        @_mcps
      end

      # @return [Hash]
      def _constants
        load_yaml_definition!
        @_constants
      end

      # @return [Frai::DirectiveDeclaration, nil]
      def _directive_declaration
        load_yaml_definition!
        @_directive_declaration
      end

      # @param input [Hash, String, nil]
      # @return [Object]
      def call(input = nil)
        new.call(input)
      end

      # Checks structure once per project_root. Subsequent calls are no-ops.
      def ensure_structure_checked!
        load_yaml_definition!
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

      # Returns the YAML path for this task.
      # Raises if neither task.yml nor task.yaml is found.
      def task_yaml_path
        path = %w[task.yml task.yaml]
                 .map { |file| File.join(task_root, file) }
                 .find { |p| File.exist?(p) }

        path || raise(Frai::Error,
          "task.yml not found for #{self}.\n" \
          "Expected: #{File.join(task_root, 'task.yml')}")
      end

      # Loads task.yml once per project_root and hydrates runtime declarations.
      # Automatically reloads when project_root changes (e.g. between test examples).
      def load_yaml_definition!
        current_root = Frai.configuration.project_root
        return if @_yaml_loaded_for == current_root

        spec = YAML.safe_load(File.read(task_yaml_path), aliases: true) || {}
        hydrate_from_yaml!(spec)
        @_yaml_loaded_for = current_root
      end

      private

      def hydrate_from_yaml!(spec)
        spec = symbolize_keys(spec)

        yaml_name = spec[:name]&.to_s
        if yaml_name && yaml_name != task_name
          raise Frai::Error,
            "task.yml name '#{yaml_name}' does not match #{self} task name '#{task_name}'."
        end

        @_mcps      = Array(spec[:mcp]).map(&:to_sym)
        @_constants = symbolize_keys(spec[:constants] || {})

        directives = symbolize_keys(spec[:directives] || spec[:directive] || {})
        @_directive_declaration = build_directive(:main, directives[:main] || {}) if directives.any?
      end

      def build_directive(name, spec)
        decl = DirectiveDeclaration.new(name)
        apply_directive_spec(decl, spec)
        decl
      end

      def apply_directive_spec(decl, spec)
        spec = symbolize_keys(spec || {})
        apply_params_spec(decl, spec[:params])
        apply_nested_uses(decl, spec[:use] || spec[:uses])
        apply_nested_runs(decl, spec[:run] || spec[:runs])
      end

      def apply_params_spec(decl, params_spec)
        return if params_spec.nil?

        params_spec = symbolize_keys(params_spec)

        decl.params do
          if params_spec.key?(:required) || params_spec.key?(:optional)
            Frai::Task.send(:apply_grouped_params, self, params_spec)
          else
            params_spec.each do |param_name, param_spec|
              Frai::Task.send(:apply_single_param, self, param_name, param_spec)
            end
          end
        end
      end

      def apply_grouped_params(params_decl, params_spec)
        each_param_entry(params_spec[:required]).each do |param_name, param_spec|
          apply_required_param(params_decl, param_name, param_spec)
        end

        each_param_entry(params_spec[:optional]).each do |param_name, param_spec|
          apply_optional_param(params_decl, param_name, param_spec)
        end
      end

      def apply_single_param(params_decl, param_name, param_spec)
        param_spec = param_spec.is_a?(Hash) ? symbolize_keys(param_spec) : { type: param_spec }

        if param_spec.key?(:required) && !param_spec[:required]
          apply_optional_param(params_decl, param_name, param_spec)
        else
          apply_required_param(params_decl, param_name, param_spec)
        end
      end

      def apply_required_param(params_decl, param_name, param_spec)
        param_spec = param_spec.is_a?(Hash) ? symbolize_keys(param_spec) : { type: param_spec }
        type = resolve_type(param_spec[:type] || param_spec)
        params_decl.required(param_name.to_sym, type)
      end

      def apply_optional_param(params_decl, param_name, param_spec)
        param_spec = param_spec.is_a?(Hash) ? symbolize_keys(param_spec) : { type: param_spec }
        type = resolve_type(param_spec[:type] || param_spec)
        params_decl.optional(param_name.to_sym, type, default: param_spec[:default])
      end

      def apply_nested_uses(decl, uses_spec)
        return if uses_spec.nil?

        each_named_entry(uses_spec).each do |child_name, child_spec|
          decl.use(child_name.to_sym) do
            Frai::Task.send(:apply_directive_spec, self, child_spec)
          end
        end
      end

      def apply_nested_runs(decl, runs_spec)
        return if runs_spec.nil?

        each_named_entry(runs_spec).each do |script_name, script_spec|
          decl.run(script_name.to_sym) do
            Frai::Task.send(:apply_script_spec, self, script_spec)
          end
        end
      end

      def apply_script_spec(script_decl, spec)
        spec = symbolize_keys(spec || {})

        input_spec = spec[:input] || spec[:params]
        if input_spec
          input_type = if input_spec.is_a?(Hash)
                         input_spec[:type] || input_spec[:class] || input_spec
                       else
                         input_spec
                       end
          script_decl.input(resolve_type(input_type))
        end

        script_decl.returns(normalize_returns_spec(spec[:returns])) if spec[:returns]
      end

      def normalize_returns_spec(returns_spec)
        case returns_spec
        when Hash
          symbolize_keys(returns_spec).each_with_object({}) do |(key, value), hash|
            hash[key.to_sym] = normalize_return_value(value)
          end
        else
          returns_spec
        end
      end

      def normalize_return_value(value)
        value = symbolize_keys(value) if value.is_a?(Hash)

        case value
        when Hash
          if value.key?(:type)
            resolve_type(value[:type])
          else
            value.transform_values { |nested| normalize_return_value(nested) }
          end
        else
          resolve_type(value)
        end
      end

      def each_named_entry(spec)
        case spec
        when Hash
          symbolize_keys(spec)
        when Array
          spec.each_with_object({}) do |entry, hash|
            if entry.is_a?(Hash)
              symbolize_keys(entry).each { |name, value| hash[name] = value }
            else
              hash[entry.to_sym] = {}
            end
          end
        else
          {}
        end
      end

      def each_param_entry(spec)
        case spec
        when Hash
          symbolize_keys(spec)
        when Array
          spec.each_with_object({}) do |entry, hash|
            if entry.is_a?(Hash)
              symbolize_keys(entry).each { |name, value| hash[name] = value }
            else
              hash[entry.to_sym] = {}
            end
          end
        else
          {}
        end
      end

      def resolve_type(value)
        case value
        when nil
          nil
        when Array
          value.map { |item| resolve_type(item) }
        when String, Symbol
          Object.const_get(value.to_s)
        else
          value
        end
      rescue NameError
        raise Frai::Error, "Unknown type '#{value}' in YAML task definition for #{task_name}"
      end

      def symbolize_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, val), hash|
            hash[key.to_sym] = symbolize_keys(val)
          end
        when Array
          value.map { |item| symbolize_keys(item) }
        else
          value
        end
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
