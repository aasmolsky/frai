# frozen_string_literal: true

module Frai
  # Thread-local store for structured values produced by ScriptTool#deliverable.
  # Agent.call returns the deliverable when set, otherwise the LLM's final text.
  module AgentDeliverable
    KEY = :frai_agent_deliverable

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
