# frozen_string_literal: true

require_relative "task_tool"
require_relative "agent_return_store"

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
  #   class AssembleOutputTool < Frai::ScriptTool
  #     task AssembleOutput::Task
  #     returns :output
  #     description "Runs the final assembly step and returns structured output."
  #
  #     def execute(data:)
  #       call_task(data: data)
  #       # => { output: { status: "ok", ... } }
  #     end
  #   end
  class ScriptTool < TaskTool
    class << self
      # Marks a script_results key as the agent return value (Agent.run#result / Agent.call output).
      # Must match return: :key in the task schema run(...) directive.
      def returns(key)
        @returns_key = key.to_sym
      end

      def returns_key
        @returns_key
      end
    end

    protected

    # Calls the declared Task and returns script_results.
    # No env switching needed — llm false tasks run in any env.
    #
    # @return [Hash{Symbol => Object}] script_results
    def call_task(**params)
      instance = invoke_task(**params)
      @_script_results = instance.script_results
      @_prompt_results = instance.prompt_results
      capture_return!
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

    def capture_return!
      key = self.class.returns_key
      return unless key

      value = script_results[key]
      AgentReturnStore.capture(value) unless value.nil?
    end
  end
end
