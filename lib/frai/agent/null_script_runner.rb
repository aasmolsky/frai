# frozen_string_literal: true

module Frai
  class Agent::NullScriptRunner
    def return_values
      {}
    end

    def run(_name, _input)
      raise Frai::Error, "Scripts are not supported in agent instructions"
    end

    def store_return(*)
      nil
    end
  end
end
