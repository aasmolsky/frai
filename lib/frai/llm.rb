# frozen_string_literal: true

module Frai
  # Applies Frai.configuration to RubyLLM once per Frai.configure call.
  # API mode only — skipped when LLM_MODEL is unset (CLI mode).
  module Llm
    PROVIDERS = {
      openai:    [/\Agpt/, /\Ao1/, /\Ao3/, /\Atext-/],
      anthropic: [/\Aclaude/],
      gemini:    [/\Agemini/],
      mistral:   [/\Amistral/]
    }.freeze

    module_function

    # @param config [Frai::Configuration]
    # @raise [Frai::Error] when model is set but api_key is missing or provider is unknown
    def apply_from!(config = Frai.configuration)
      model = config.model.to_s.strip
      return if model.empty?

      key = config.api_key.to_s.strip
      raise Frai::Error, "LLM_API_KEY is not set" if key.empty?

      provider = detect_provider!(model)

      require "ruby_llm"

      RubyLLM.configure do |c|
        case provider
        when :openai    then c.openai_api_key    = key
        when :anthropic then c.anthropic_api_key = key
        when :gemini    then c.gemini_api_key    = key
        when :mistral   then c.mistral_api_key   = key
        end
      end
    end

    def detect_provider!(model)
      PROVIDERS.each do |provider, patterns|
        return provider if patterns.any? { |pattern| model.match?(pattern) }
      end

      raise Frai::Error,
        "Cannot determine LLM provider for model #{model.inspect}. " \
        "Use a recognized prefix: gpt-, claude-, gemini-, mistral-."
    end

    def reset!
      # Reserved for test isolation; RubyLLM is stubbed at adapter/agent boundaries in specs.
    end
  end
end
