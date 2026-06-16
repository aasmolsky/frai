# frozen_string_literal: true

require "ruby_llm/tool"

require_relative "deep_symbolize"

module Frai
  # Shared base for {PromptTool} and {ScriptTool}.
  #
  # LLM providers pass tool arguments with string keys at every nesting level.
  # Task param schemas (dry-schema) expect symbol keys. This class deep-symbolizes
  # Hash and Array argument values in {#call} (LLM → +execute+) and in {#call_task}
  # (tool → Task), and exposes an overridable {#normalize_param} hook.
  #
  # @example per-parameter transform
  #   def normalize_param(name, value)
  #     value = super
  #     return unwrap_envelope(value) if name == :data
  #     value
  #   end
  class TaskTool < RubyLLM::Tool
    class << self
      def task(klass = nil)
        return @task_class unless klass

        @task_class = klass
      end

      # Deep-symbolizes constructor state (payload, config) for {#state}.
      def normalize_state(value)
        DeepSymbolize.call(value)
      end
    end

    # @param state [Hash, nil] optional agent-local state (e.g. payload from +tools do+)
    def initialize(state = nil)
      @state = self.class.normalize_state(state) unless state.nil?
    end

    # Normalized state from +initialize+, or +nil+ when omitted.
    attr_reader :state

    # Deep-normalizes LLM tool arguments before +execute+.
    def call(args)
      normalized_args = normalize_tool_args(args)
      validation_error = validate_keyword_arguments(normalized_args)
      return { error: "Invalid tool arguments: #{validation_error}" } if validation_error

      RubyLLM.logger.debug { "Tool #{name} called with: #{normalized_args.inspect}" }
      result = execute(**normalized_args)
      RubyLLM.logger.debug { "Tool #{name} returned: #{result.inspect}" }
      result
    end

    protected

    # Hook for subclasses. +value+ is already deep-symbolized when it is a Hash or Array.
    #
    # @param _name [Symbol] keyword name from +execute+
    # @param value [Object]
    # @return [Object]
    def normalize_param(_name, value)
      value
    end

    def normalize_tool_args(args)
      normalize_args(args).each_with_object({}) do |(name, value), result|
        result[name] = normalize_param(name, DeepSymbolize.call(value))
      end
    end

    def normalize_task_params(params)
      params.each_with_object({}) do |(name, value), result|
        sym = name.to_sym
        result[sym] = normalize_param(sym, DeepSymbolize.call(value))
      end
    end

    def invoke_task(**params)
      normalized = normalize_task_params(params)
      instance   = self.class.task.new
      instance.call(normalized.empty? ? nil : normalized)
      instance
    end
  end
end
