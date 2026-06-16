# frozen_string_literal: true

require "ruby_llm/agent"

require_relative "agent_return_store"

module Frai
  # Base class for all Frai agents.
  #
  # Instructions — three modes (mutually exclusive):
  #
  #   instructions                         # → agents/<name>/directives/instructions.md.erb
  #   instructions "You are helpful."      # inline — no directive files allowed
  #   instructions do                      # composite — declare tree with `use`, compose in ERB
  #     use :instructions do
  #       use :guidelines
  #     end
  #   end
  class Agent < RubyLLM::Agent
    # Returned by Agent.run — bundles primary output with script result and LLM message.
    # output  — result when set, otherwise the LLM's final response (Agent.call returns this)
    # result  — structured value from ScriptTool#returns (script_results key), or nil
    # message — the LLM's final response (String or Hash when schema is set)
    AgentResult = Struct.new(:output, :result, :message, keyword_init: true)

    class << self
      def inherited(subclass)
        super
        %i[@_instructions_mode @_instructions_declaration].each do |ivar|
          next unless instance_variable_defined?(ivar)

          subclass.instance_variable_set(ivar, instance_variable_get(ivar))
        end
      end

      # @return [Symbol, nil] :file, :inline, :composite
      def instructions_mode
        @_instructions_mode
      end

      # @return [Frai::DirectiveDeclaration, nil]
      def instructions_declaration
        @_instructions_declaration
      end

      # Runs the agent and returns the primary output (script result or LLM response).
      def call(message = nil, **kwargs)
        run(message, **kwargs).output
      end

      # Runs the agent and returns AgentResult with output, result, and message.
      def run(message = nil, **kwargs)
        message = normalize_agent_message(message)
        ensure_not_nested!
        ensure_structure_checked!
        return dry_run_result(message) if Frai.configuration.dry_run?

        ensure_production_model!

        Frai.run_with_task_context(:agent_tool) do
          AgentReturnStore.with_store do
            content = new(model: Frai.configuration.model, **kwargs).ask(message).content
            result  = AgentReturnStore.value
            if requires_script_return? && result.nil?
              raise Frai::Error,
                "#{self} expected a script return but finished without a successful `returns` tool call.\n" \
                "Ensure the agent calls the ScriptTool with `returns`, or remove `returns` from the tool."
            end

            AgentResult.new(
              output:  result || content,
              result:  result,
              message: content
            )
          end
        end
      end

      # True when any ScriptTool on this agent declares `returns`.
      def requires_script_return?
        AgentToolsResolver.script_tools_with_returns(self).any?
      end

      # Checks agent structure once per project_root (returns tools, directives).
      # Runs automatically on Agent.run / Agent.call — same idea as Task.ensure_structure_checked!
      def ensure_structure_checked!
        return if @_structure_checked_for == Frai.configuration.project_root

        AgentStructureChecker.new(self).check!
        @_structure_checked_for = Frai.configuration.project_root
      end

      def reset_structure_check!
        @_structure_checked_for = nil
      end

      # Mode A — load agents/<agent>/directives/instructions.md.erb
      # Mode B — inline string (no directive files on disk)
      # Mode C — instructions do ... end with nested `use` declarations
      def instructions(text = nil, **locals, &block)
        if block_given?
          builder = InstructionsBuilder.new
          builder.instance_eval(&block)
          @_instructions_mode = :composite
          @_instructions_declaration = builder.build!
          super({ prompt: @_instructions_declaration.name.to_s, locals: locals })
        elsif text.nil? && locals.empty?
          @_instructions_mode = :file
          @_instructions_declaration = DirectiveDeclaration.new(:instructions)
          super()
        else
          @_instructions_mode = :inline
          @_instructions_declaration = nil
          super(text, **locals, &block)
        end
      end

      def directives(*)
        raise Frai::Error,
          "directives do was removed. Use `instructions`, `instructions \"...\"`, or `instructions do`."
      end

      def _agent_directive_path
        base = name.to_s.split("::").last || ""
        base = base.sub(/Agent\z/, "").sub(/_\z/, "")
        base.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      # Renders agent instructions via Frai::DirectiveRenderer (supports `use` in ERB).
      def render_prompt(name, chat:, inputs:, locals:)
        case instructions_mode
        when :file, :composite
          render_frai_instructions(inputs, locals)
        else
          super
        end
      end

      private

      def normalize_agent_message(message)
        message.nil? || message.to_s.strip.empty? ? "Complete the task." : message
      end

      def ensure_not_nested!
        return unless Frai.configuration.inside_agent_tool?

        raise Frai::Error,
          "#{self} cannot be called from within an agent context — agents cannot be nested."
      end

      def dry_run_result(message)
        warn "Frai [#{Frai.configuration.env}]: dry run — agent LLM not called."
        label = "[dry run] #{name}: #{message}"
        AgentResult.new(output: label, result: nil, message: label)
      end

      def ensure_production_model!
        model = Frai.configuration.model
        return if model && !model.to_s.strip.empty?

        raise Frai::Error,
          "LLM_MODEL is required for agents in production. Set LLM_MODEL in .env or config/frai.rb."
      end

      def render_frai_instructions(inputs, locals)
        declaration = instructions_declaration
        renderer    = DirectiveRenderer.new(
          nil,
          Frai.configuration.project_root,
          NullScriptRunner.new,
          {},
          declaration,
          agent_name: _agent_directive_path
        )
        renderer.render(declaration, normalize_instruction_inputs(inputs, locals))
      end

      def normalize_instruction_inputs(inputs, locals)
        hash = case inputs
               when Hash  then inputs.transform_keys(&:to_sym)
               when nil   then {}
               else            { input: inputs }
               end
        hash.merge(locals.transform_keys(&:to_sym))
      end

      def prompt_path_for(name)
        Pathname.new(Frai.configuration.project_root)
                .join("agents", _agent_directive_path, "directives", "#{name}.md.erb")
      end
    end
  end
end

require_relative "agent/null_script_runner"
require_relative "agent/instructions_builder"
