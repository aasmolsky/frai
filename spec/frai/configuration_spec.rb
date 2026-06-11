# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::Configuration do
  after { Frai.reset! }

  describe "#env" do
    it "does not change when agent tool context is active" do
      Frai.configure { |c| c.env = :development }

      Frai.run_with_task_context(:agent_tool) do
        expect(Frai.configuration.env).to eq(:development)
        expect(Frai.configuration.dry_run?).to be true
        expect(Frai.configuration.inside_agent_tool?).to be true
      end

      expect(Frai.configuration.inside_agent_tool?).to be false
    end
  end

  describe "#dry_run?" do
    it "is true for development and test" do
      Frai.configure { |c| c.env = :development }
      expect(Frai.configuration.dry_run?).to be true

      Frai.configure { |c| c.env = :test }
      expect(Frai.configuration.dry_run?).to be true
    end

    it "is false for production" do
      Frai.configure { |c| c.env = :production }
      expect(Frai.configuration.dry_run?).to be false
    end
  end

  describe "#non_production?" do
    it "is true only for test, not development" do
      Frai.configure { |c| c.env = :test }
      expect(Frai.configuration.non_production?).to be true

      Frai.configure { |c| c.env = :development }
      expect(Frai.configuration.non_production?).to be false
    end
  end

  describe ".coerce_env!" do
    it "rejects unknown values" do
      expect { described_class.coerce_env!("agent") }
        .to raise_error(Frai::Error, /Invalid FRAI_ENV/)
    end
  end
end
