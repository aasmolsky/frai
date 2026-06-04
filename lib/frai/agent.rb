module Frai
  # Base class for all Frai agents.
  #
  # An agent orchestrates tasks and tools dynamically. Unlike pipelines,
  # agents can make decisions, call tools, and loop based on LLM responses.
  # Agents share the same external contract as tasks: {.call}.
  #
  # @example
  #   class ObjectComparisonAgent < Frai::Agent
  #     tool FetchDataTask
  #     tool AnalyzeItemTask
  #   end
  #
  #   ObjectComparisonAgent.call("compare object_a, object_b, object_c")
  class Agent
    # Instantiates and calls the agent.
    #
    # @param input [Object, nil] input passed to the agent
    # @return [Object] result returned by the agent
    def self.call(input = nil)
      new.call(input)
    end

    # Runs the agent logic.
    # Override in subclasses to implement orchestration.
    #
    # @param input [Object, nil] input passed to the agent
    # @return [Object] agent result
    def call(input = nil)
      raise NotImplementedError, "#{self.class}#call is not implemented"
    end
  end
end
