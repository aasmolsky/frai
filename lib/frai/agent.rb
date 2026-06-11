# frozen_string_literal: true

require "ruby_llm/agent"

module Frai
  # Base class for all Frai agents.
  #
  # Wraps RubyLLM::Agent and adds a conventional .call interface.
  # Declare tools and instructions using the RubyLLM DSL, then call the agent
  # with keyword arguments matching your declared `inputs`.
  #
  # Optionally declare a directive schema so `frai check` can validate that all
  # referenced `.md.erb` files exist and there are no orphan files on disk:
  #
  #   class DataAnalysisAgent < BaseAgent
  #     inputs :payload
  #
  #     schema do
  #       directive :instructions           # agents/data_analysis/directives/instructions.md.erb
  #       directive :tool_descriptions      # agents/data_analysis/directives/tool_descriptions.md.erb
  #     end
  #
  #     instructions               # → agents/data_analysis/directives/instructions.md.erb
  #     tools do ... end
  #   end
  #
  #   DataAnalysisAgent.call("Complete the task.", payload: data)
  class Agent < RubyLLM::Agent
    # Tracks which directive files an agent declares via `schema do directive :name end`.
    # Used exclusively by AgentStructureChecker — has no runtime effect.
    class DirectiveSchema
      attr_reader :directive_names

      def initialize
        @directive_names = []
      end

      # Declares that agents/<agent_name>/directives/<name>.md.erb must exist.
      # Raises if the same name is declared twice.
      def directive(name)
        name = name.to_sym
        raise Frai::Error, "directive :#{name} already declared" if @directive_names.include?(name)

        @directive_names << name
      end
    end

    class << self
      # Runs the agent by sending an initial message and returning the response.
      # Tasks invoked via PromptTool/ScriptTool run in :agent_tool context (prompt only).
      #
      # @param message [String] initial message / task description for the agent
      # @param kwargs [Hash] input values declared via `inputs :name`
      # @return [String] agent's final response
      def call(message = "Complete the task.", **kwargs)
        raise Frai::Error,
          "#{self} cannot be called from within an agent context — agents cannot be nested." if Frai.configuration.inside_agent_tool?

        if Frai.configuration.dry_run?
          warn "Frai [#{Frai.configuration.env}]: dry run — agent LLM not called."
          return "[dry run] #{name}: #{message}"
        end

        Frai.run_with_task_context(:agent_tool) do
          new(**kwargs).ask(message)
        end
      end

      # Declares which directive files this agent uses (setter), or returns the
      # current declaration (getter).
      #
      # Overrides RubyLLM::Agent#schema intentionally — Frai agents are
      # orchestrators that return text; structured output belongs in tasks.
      #
      #   schema do
      #     directive :instructions
      #     directive :tool_descriptions
      #   end
      def schema(&block)
        if block_given?
          ds = DirectiveSchema.new
          ds.instance_eval(&block)
          @_agent_directive_schema = ds
        else
          @_agent_directive_schema
        end
      end

      # Snake-case folder name for this agent under agents/.
      # Used by AgentStructureChecker and prompt_path_for.
      #
      # Example: DataPipeline::DataAnalysisAgent → "data_analysis"
      def _agent_directive_path
        base = name.to_s.split("::").last || ""
        base = base.sub(/Agent\z/, "").sub(/_\z/, "")
        base.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      private

      # Resolves instruction file from agents/<agent_name>/directives/<name>.md.erb
      # so agents follow the same convention as tasks.
      #
      # Called by the RubyLLM DSL when `instructions` is used without an argument:
      #
      #   class DataAnalysisAgent < BaseAgent
      #     instructions   # → agents/data_analysis/directives/instructions.md.erb
      #   end
      def prompt_path_for(name)
        Pathname.new(Frai.configuration.project_root)
                .join("agents", _agent_directive_path, "directives", "#{name}.md.erb")
      end
    end
  end
end
