# frozen_string_literal: true

require "ruby_llm/tool"

module Frai
  # Base class for agent tools that wrap a Frai Task and return its rendered prompt.
  #
  # Returns prompt_results — a Hash with:
  #   :prompt       — the fully rendered directive text
  #   :<script_key> — symbolic reference for each script that ran (value == key)
  #
  # The symbolic keys serve two purposes:
  #   1. They signal to the agent which script results are available via a paired ScriptTool
  #   2. They act as markers inside the prompt text when used as :symbol literals
  #      in the directive template — allowing the agent to locate where data belongs
  #      without confusing script references with regular words
  #
  # Directive convention:
  #   Use :<script_key> literally in the template text as a placeholder.
  #   Regular words (no colon) are never confused with script markers.
  #
  #   % run(:fetch_context, params: :query, return: :context)
  #
  #   Here is the :context to review.    ← :context is a script marker
  #   Review the input above.            ← "input" is just a word
  #
  # For simple cases where the LLM passes all params directly, use `.for`:
  #
  #   tools do
  #     [Frai::PromptTool.for(FetchItems::Task, description: "Fetches raw data")]
  #   end
  #
  # @example task with scripts — pair with a ScriptTool to expose actual data
  #   class GetReportPromptTool < Frai::PromptTool
  #     task PrepareReport::Task
  #     description "Returns the report writing prompt."
  #
  #     param :llm_data, type: "object", desc: "Structured analysis"
  #
  #     def initialize(payload) = @payload = payload
  #
  #     def execute(llm_data:)
  #       call_task(language: @payload[:language], data: @payload[:data], llm_data: llm_data)
  #       # returns:
  #       # {
  #       #   prompt:        "You are a review analyst...\nHere is the :prepared_data...",
  #       #   prepared_data: :prepared_data   ← key == value, signals a script ran
  #       # }
  #     end
  #   end
  class PromptTool < RubyLLM::Tool
    class << self
      def task(klass = nil)
        return @task_class unless klass

        @task_class = klass
      end

      # Factory for the common case — LLM provides all params at call time.
      # Returns an anonymous PromptTool subclass ready to pass to `tools do`.
      #
      # @param task_class [Class] Frai::Task subclass to wrap
      # @param description [String, nil] tool description for the LLM;
      #   defaults to the task class name
      # @return [Class] anonymous PromptTool subclass
      def for(task_class, description: nil)
        klass = Class.new(self)
        klass.task(task_class)
        klass.description(description || task_class.name.to_s)
        klass.define_method(:execute) { |**params| call_task(**params) }
        klass
      end
    end

    protected

    # Calls the declared Task inside :agent_tool context and returns prompt_results.
    #
    # prompt_results contains:
    #   :prompt       — the rendered directive text
    #   :<script_key> — symbolic reference (key == value) for each script that ran
    #
    # To get actual script data pair this tool with a ScriptTool on the same task,
    # or call Task.run outside of agent context.
    #
    # @return [Hash] prompt_results
    def call_task(**params)
      raise Frai::Error,
        "#{self.class} must be called within an agent context. " \
        "Use Frai::Agent.call — it sets the agent tool context for the duration of the run." unless Frai.configuration.inside_agent_tool?

      instance = self.class.task.new
      instance.call(params.any? ? params : nil)
      @_prompt_results = instance.prompt_results
      prompt_results
    end

    # Rendered prompt + symbolic script references from the last call_task.
    # :prompt       — the rendered directive text
    # :<script_key> — symbolic reference to each script that ran (use Task.run or ScriptTool to get actual data)
    # @return [Hash{Symbol => Object}]
    def prompt_results
      @_prompt_results || {}
    end
  end
end
