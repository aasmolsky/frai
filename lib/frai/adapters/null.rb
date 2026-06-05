module Frai
  module Adapters
    # Null adapter for testing and development.
    # Does not make any real LLM calls — returns the rendered prompt as-is.
    # Useful for verifying that directives render correctly without API keys.
    #
    # @example
    #   Frai.configure do |config|
    #     config.adapter = :null
    #   end
    #
    #   AnalyzeItemTask.call(name: "iPhone 15", category: "phones")
    #   # => returns the rendered prompt string
    class Null
      # @param prompt [String] the rendered prompt
      # @return [String] returns the prompt unchanged
      def complete(prompt, mcp_servers: [])
        prompt
      end
    end
  end
end
