# frozen_string_literal: true

module Frai
  # Thread-local store for structured values produced by ScriptTool#returns.
  # Agent.run exposes them as AgentResult#result; Agent.call returns output (result or LLM text).
  module AgentReturnStore
    KEY = :frai_agent_return

    class << self
      def with_store
        previous = Thread.current[KEY]
        Thread.current[KEY] = nil
        yield
      ensure
        Thread.current[KEY] = previous
      end

      def capture(value)
        Thread.current[KEY] = value unless value.nil?
      end

      def value
        Thread.current[KEY]
      end
    end
  end
end
