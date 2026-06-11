# frozen_string_literal: true

require "ruby_llm/agent"

module Frai
  # Base class for all Frai agents.
  #
  # Wraps RubyLLM::Agent and adds a conventional .call interface.
  # Declare tools and instructions using the RubyLLM DSL, then call the agent
  # with keyword arguments matching your declared `inputs`.
  #
  # @example
  #   class ReviewAgent < Frai::Agent
  #     inputs :payload
  #
  #     tools do
  #       [AnalyzeTool.new(payload), BuildTool.new(payload)]
  #     end
  #
  #     instructions "You are an expert analyst..."
  #   end
  #
  #   ReviewAgent.call("Analyze the reviews.", payload: data)
  class Agent < RubyLLM::Agent
    # Runs the agent by sending an initial message and returning the response.
    # Sets FRAI_ENV=agent for the duration so PromptTools render prompts instead
    # of calling the LLM directly.
    #
    # @param message [String] initial message / task description for the agent
    # @param kwargs [Hash] input values declared via `inputs :name`
    # @return [String] agent's final response
    def self.call(message = "Complete the task.", **kwargs)
      raise Frai::Error,
        "#{self} cannot be called from within an agent context — agents cannot be nested." if Frai.configuration.agent?

      Thread.current[:frai_env_override] = :agent
      new(**kwargs).ask(message)
    ensure
      Thread.current[:frai_env_override] = nil
    end
  end
end
