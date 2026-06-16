# frozen_string_literal: true

module Frai
  # Resolves tool classes declared on an agent (for structure checks and runtime guards).
  module AgentToolsResolver
    class << self
      # @param agent_class [Class<Frai::Agent>]
      # @return [Array<Class>]
      def tool_classes(agent_class)
        raw = agent_class.tools
        list = if raw.is_a?(Proc)
          build_runtime(agent_class).instance_exec(&raw)
        else
          raw || []
        end

        Array(list).map { |entry| entry.is_a?(Class) ? entry : entry.class }
      end

      # @param agent_class [Class<Frai::Agent>]
      # @return [Array<Class<Frai::ScriptTool>>]
      def script_tools_with_returns(agent_class)
        tool_classes(agent_class).select do |klass|
          klass < Frai::ScriptTool && klass.returns_key
        end
      end

      private

      def build_runtime(agent_class)
        Object.new.tap do |runtime|
          agent_class.inputs.each do |name|
            sym = name.to_sym
            runtime.define_singleton_method(name) { sym == :payload ? {} : nil }
          end
        end
      end
    end
  end
end
