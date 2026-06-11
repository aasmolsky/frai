# frozen_string_literal: true

require "ruby_llm/tool"

module Frai
  # Base class for agent tools that wrap a Frai Task with `llm false`.
  #
  # ScriptTool wraps tasks that only run scripts (no LLM call). These are
  # pure data-processing steps — the task runs its scripts, builds the result,
  # and returns it directly to the agent as structured data.
  #
  # @example
  #   class BuildReportTool < Frai::ScriptTool
  #     task BuildReport::Task
  #     description "Builds the final report from prepared data and LLM output."
  #
  #     params({ type: "object", properties: { ... }, required: [...] })
  #
  #     def initialize(payload)
  #       @payload = payload
  #     end
  #
  #     def execute(prepared_data:, llm_report:)
  #       call_task(data: prepared_data, llm_data: llm_report)
  #     end
  #   end
  class ScriptTool < RubyLLM::Tool
    class << self
      def task(klass = nil)
        return @task_class unless klass

        @task_class = klass
      end
    end

    protected

    # Calls the declared Task directly (no env switching needed — llm false).
    def call_task(**params)
      self.class.task.call(**params)
    end
  end
end
