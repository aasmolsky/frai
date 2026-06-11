# frozen_string_literal: true

require "ruby_llm/tool"

module Frai
  # Base class for agent tools that wrap a Frai Task with `llm false`.
  #
  # Calls the task, captures script outputs, and returns script_results —
  # the actual data produced by scripts, keyed by their return key.
  #
  # Prompt-related metadata is also available via prompt_results after call_task,
  # but the default return value is script_results.
  #
  # @example
  #   class BuildReportTool < Frai::ScriptTool
  #     task BuildReport::Task
  #     description "Builds the final report from prepared data and LLM output."
  #
  #     def initialize(payload)
  #       @payload = payload
  #     end
  #
  #     def execute(prepared_data:, llm_report:)
  #       call_task(data: prepared_data, llm_data: llm_report)
  #       # returns script_results => { report: { item_id: "...", ... } }
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

    # Calls the declared Task and returns script_results.
    # No env switching needed — llm false tasks run in any env.
    #
    # @return [Hash{Symbol => Object}] script_results
    def call_task(**params)
      instance = self.class.task.new
      instance.call(params.any? ? params : nil)
      @_script_results = instance.script_results
      @_prompt_results = instance.prompt_results
      script_results
    end

    # Actual script outputs from the last call_task, keyed by return key.
    # @return [Hash{Symbol => Object}]
    def script_results
      @_script_results || {}
    end

    # Rendered prompt + symbolic script references from the last call_task.
    # @return [Hash{Symbol => Object}]
    def prompt_results
      @_prompt_results || {}
    end
  end
end
