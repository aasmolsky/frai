# frozen_string_literal: true

module Frai
  module Adapters
    # Null adapter — used automatically when no LLM model is configured (model: nil).
    # Returns the rendered prompt as-is without making any API calls.
    # Useful for verifying that directives render correctly without API keys.
    #
    # Accepts the same interface as RubyLlm so adapters are interchangeable.
    #
    # @example Null adapter is selected automatically when model is nil:
    #   Frai.configure do |config|
    #     # config.model = nil  (default) — Null adapter is used
    #   end
    #
    #   AnalyzeItem::Task.call(name: "iPhone 15")
    #   # => returns the rendered prompt string, no API call made
    class Null
      # @param prompt [String] the rendered prompt
      # @param mcp_servers [Array] accepted for interface compatibility, intentionally ignored
      # @param schema [Class, nil] accepted for interface compatibility, intentionally ignored
      # @return [String] the prompt unchanged
      def complete(prompt, mcp_servers: [], schema: nil)
        prompt
      end
    end
  end
end
