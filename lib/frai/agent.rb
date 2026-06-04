# frozen_string_literal: true

module Frai
  # Base class for all Frai agents.
  #
  # An agent orchestrates tasks dynamically — it can decide which tasks
  # to call, in what order, and how many times, based on intermediate results.
  #
  # @example
  #   class ResearchAgent < Frai::Agent
  #     def call(input)
  #       data    = FetchDataTask.call(input)
  #       summary = SummarizeTask.call(data)
  #       summary
  #     end
  #   end
  #
  #   ResearchAgent.call("topic to research")
  class Agent
    def self.call(input = nil)
      new.call(input)
    end

    def call(input = nil)
      raise NotImplementedError, "#{self.class}#call is not implemented"
    end
  end
end
