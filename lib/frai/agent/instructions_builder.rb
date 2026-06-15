# frozen_string_literal: true

module Frai
  class Agent::InstructionsBuilder
    def use(name, &block)
      if @root
        raise Frai::Error,
          "instructions do accepts only one top-level `use :entry` block"
      end

      @root = DirectiveDeclaration.new(name)
      @root.instance_eval(&block) if block_given?
    end

    def build!
      raise Frai::Error, "instructions do must declare `use :entry`" unless @root

      @root
    end
  end
end
