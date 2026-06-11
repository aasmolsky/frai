# frozen_string_literal: true

require "ruby_llm/tool"

module Frai
  # Base class for agent tools that wrap a Frai Task and return its rendered prompt.
  #
  # When an agent needs the LLM to reason over a complex context (e.g. a list of
  # reviews), the task renders the prompt in :agent mode — running scripts and
  # building the directive — but skips the LLM call. The rendered string is
  # returned to the agent as a tool result, and the agent's own LLM processes it.
  #
  # This keeps large raw data (e.g. review arrays) out of the LLM's tool-call
  # arguments — they are captured at tool instantiation time via a constructor.
  #
  # @example
  #   class AnalyzeReviewsPromptTool < Frai::PromptTool
  #     task AnalyzeReviews::Task
  #     description "Generates the review analysis prompt."
  #
  #     def initialize(payload)
  #       @payload = payload
  #     end
  #
  #     def execute
  #       call_task(place_id: @payload[:place_id], reviews: @payload[:reviews], ...)
  #     end
  #   end
  class PromptTool < RubyLLM::Tool
    class << self
      def task(klass = nil)
        return @task_class unless klass

        @task_class = klass
      end
    end

    protected

    # Calls the declared Task in :agent mode (skips LLM, returns rendered prompt).
    # Raises if called outside of agent context — env must be :agent.
    def call_task(**params)
      raise Frai::Error,
        "#{self.class} must be called within an agent context. " \
        "Use Frai::Agent.call — it sets FRAI_ENV=agent for the duration of the run." unless Frai.configuration.agent?

      self.class.task.call(**params)
    end
  end
end