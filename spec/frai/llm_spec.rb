# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::Llm do
  after { Frai.reset! }

  describe ".apply_from!" do
    it "does nothing when model is unset (CLI mode)" do
      expect(RubyLLM).not_to receive(:configure)

      described_class.apply_from!(Frai.configuration)
    end

    it "does nothing when model is whitespace only" do
      Frai.configuration.model = "   "

      expect(RubyLLM).not_to receive(:configure)

      described_class.apply_from!(Frai.configuration)
    end

    it "raises when model is set but api_key is missing" do
      Frai.configuration.model = "gpt-4o"

      expect { described_class.apply_from!(Frai.configuration) }
        .to raise_error(Frai::Error, /LLM_API_KEY is not set/)
    end

    it "raises when api_key is whitespace only" do
      Frai.configuration.model   = "gpt-4o"
      Frai.configuration.api_key = "   "

      expect { described_class.apply_from!(Frai.configuration) }
        .to raise_error(Frai::Error, /LLM_API_KEY is not set/)
    end

    it "raises for an unrecognized model prefix" do
      Frai.configuration.model   = "my-custom-model"
      Frai.configuration.api_key = "test-key"

      expect { described_class.apply_from!(Frai.configuration) }
        .to raise_error(Frai::Error, /Cannot determine LLM provider/)
    end

    {
      openai:    { model: "gpt-4o",          key_attr: :openai_api_key },
      anthropic: { model: "claude-opus-4-6", key_attr: :anthropic_api_key },
      gemini:    { model: "gemini-2.0-flash", key_attr: :gemini_api_key },
      mistral:   { model: "mistral-large",   key_attr: :mistral_api_key }
    }.each do |provider, attrs|
      it "configures #{provider} for #{attrs[:model]}", :aggregate_failures do
        Frai.configuration.model   = attrs[:model]
        Frai.configuration.api_key = "#{provider}-key"

        described_class.apply_from!(Frai.configuration)

        expect(RubyLLM.config.public_send(attrs[:key_attr])).to eq("#{provider}-key")
      end
    end

    it "strips whitespace from model and api_key", :aggregate_failures do
      Frai.configuration.model   = "  gpt-4o  "
      Frai.configuration.api_key = "  test-key  "

      described_class.apply_from!(Frai.configuration)

      expect(RubyLLM.config.openai_api_key).to eq("test-key")
    end
  end

  describe "via Frai.configure" do
    it "applies RubyLLM config after the block" do
      Frai.configure do |c|
        c.model   = "claude-opus-4-6"
        c.api_key = "anthropic-key"
      end

      expect(RubyLLM.config.anthropic_api_key).to eq("anthropic-key")
    end
  end
end
