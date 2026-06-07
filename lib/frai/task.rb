# frozen_string_literal: true

require "kdl"

module Frai
  # Base class for all Frai tasks.
  #
  # The task contract lives entirely in tasks/<name>/task.kdl.
  # The Ruby class is a thin entrypoint only — it provides TaskNameTask.call(params).
  # All params, directives, mcp and constants are declared in KDL.
  #
  # Calling convention:
  #   TaskNameTask.call("plain string input")
  #   TaskNameTask.call(param_name: value, ...)   # when params declared in task.kdl
  #
  # Execution order:
  #   1. Load and parse task.kdl
  #   2. Validate params against task.kdl declarations
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
        load_kdl_definition!
        @_mcps
      end

      # @return [Hash]
      def _constants
        load_kdl_definition!
        @_constants
      end

      # @return [Frai::DirectiveDeclaration, nil]
      def _directive_declaration
        load_kdl_definition!
        @_directive_declaration
      end

      # @param input [Hash, String, nil]
      # @return [Object]
      def call(input = nil)
        new.call(input)
      end

      # Checks structure once per project_root. Subsequent calls are no-ops.
      def ensure_structure_checked!
        load_kdl_definition!
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

      # Returns the KDL path for this task.
      # Raises if task.kdl is not found.
      def task_kdl_path
        path = File.join(task_root, "task.kdl")
        return path if File.exist?(path)

        raise(Frai::Error,
          "task.kdl not found for #{self}.\n" \
          "Expected: #{path}")
      end

      # Loads task.kdl once per project_root and hydrates runtime declarations.
      # Automatically reloads when project_root changes (e.g. between test examples).
      def load_kdl_definition!
        current_root = Frai.configuration.project_root
        return if @_kdl_loaded_for == current_root

        doc = KDL.parse(File.read(task_kdl_path))
        hydrate_from_kdl!(doc)
        @_kdl_loaded_for = current_root
      end

      private

      def hydrate_from_kdl!(doc)
        task_node = doc.nodes.find { |n| n.name == "task" }
        raise Frai::Error, "No 'task' node found in task.kdl for #{task_name}" unless task_node

        kdl_name = prop(task_node, "name")
        if kdl_name && kdl_name != task_name
          raise Frai::Error,
            "task.kdl name '#{kdl_name}' does not match #{self} task name '#{task_name}'."
        end

        @_mcps = kdl_children(task_node, "mcp").map { |n| arg(n).to_sym }

        @_constants = kdl_children(task_node, "const").each_with_object({}) do |n, h|
          h[arg(n, 0).to_sym] = arg(n, 1)
        end

        main_node = kdl_children(task_node, "directive").find { |n| prop(n, "name") == "main" }
        @_directive_declaration = build_directive_from_kdl(:main, main_node) if main_node
      end

      def build_directive_from_kdl(name, node)
        return nil unless node

        decl = DirectiveDeclaration.new(name)
        apply_directive_kdl(decl, node)
        decl
      end

      def apply_directive_kdl(decl, node)
        return unless node

        param_nodes = kdl_children(node, "param")
        if param_nodes.any?
          decl.params do
            param_nodes.each do |p|
              param_name = Frai::Task.send(:prop, p, "name").to_sym
              type_str   = Frai::Task.send(:prop, p, "type")
              required   = Frai::Task.send(:prop, p, "required")
              default    = Frai::Task.send(:prop, p, "default")
              type       = Frai::Task.send(:resolve_type, type_str)

              if required == false
                optional(param_name, type, default: default)
              else
                required(param_name, type)
              end
            end
          end
        end

        kdl_children(node, "use").each do |use_node|
          use_name = (prop(use_node, "name") || arg(use_node)).to_sym
          decl.use(use_name) do
            Frai::Task.send(:apply_directive_kdl, self, use_node)
          end
        end

        kdl_children(node, "run").each do |run_node|
          script_name = prop(run_node, "name").to_sym
          decl.run(script_name) do
            Frai::Task.send(:apply_script_kdl, self, run_node)
          end
        end
      end

      def apply_script_kdl(script_decl, node)
        input_node = kdl_child(node, "input")
        if input_node
          script_decl.input(resolve_type(prop(input_node, "type")))
        end

        returns_nodes = kdl_children(node, "returns")
        if returns_nodes.any?
          schema = returns_nodes.each_with_object({}) do |r, h|
            h[prop(r, "name").to_sym] = resolve_type(prop(r, "type"))
          end
          script_decl.returns(schema)
        end
      end

      # KDL helpers

      def prop(node, key)
        node.properties[key]&.value
      end

      def arg(node, index = 0)
        node.arguments[index]&.value
      end

      def kdl_children(node, name)
        (node&.children || []).select { |n| n.name == name }
      end

      def kdl_child(node, name)
        (node&.children || []).find { |n| n.name == name }
      end

      def resolve_type(value)
        return nil if value.nil?

        case value
        when Array
          value.map { |item| resolve_type(item) }
        when String, Symbol
          Object.const_get(value.to_s)
        else
          value
        end
      rescue NameError
        raise Frai::Error, "Unknown type '#{value}' in task.kdl for #{task_name}"
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
