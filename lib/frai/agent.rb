# frozen_string_literal: true

require "ruby_llm/agent"

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

      # Runs the agent by sending an initial message and returning the response.
      def call(message = nil, **kwargs)
        message = "Complete the task." if message.nil? || message.to_s.strip.empty?

        raise Frai::Error,
          "#{self} cannot be called from within an agent context — agents cannot be nested." if Frai.configuration.inside_agent_tool?

        if Frai.configuration.dry_run?
          warn "Frai [#{Frai.configuration.env}]: dry run — agent LLM not called."
          return "[dry run] #{name}: #{message}"
        end

        model = Frai.configuration.model
        if model.nil? || model.to_s.strip.empty?
          raise Frai::Error,
            "LLM_MODEL is required for agents in production. Set LLM_MODEL in .env or config/frai.rb."
        end

        Frai.run_with_task_context(:agent_tool) do
          new(model: model, **kwargs).ask(message).content
        end
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
