# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::Agent do
  after { Frai.reset! }

  let(:agent_class) do
    Class.new(described_class) do
      def self.name = "DemoAgent"

      instructions "Do the thing."

      tools { [] }
    end
  end

  before do
    stub_const("DemoAgent", agent_class)
  end

  let(:project_root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(project_root) }

  describe "instructions API" do
    it "does not override RubyLLM schema" do
      expect(agent_class.schema).to be_nil
    end

    it "rejects the removed directives DSL" do
      expect { agent_class.directives {} }
        .to raise_error(Frai::Error, /directives do was removed/)
    end
  end

  describe ".call in production" do
    before do
      Frai.configure do |c|
        c.project_root = project_root
        c.env          = :production
        c.model        = "gpt-4o"
        c.api_key      = "test-key"
      end
    end

    it "delegates to the agent with the configured model and returns message content" do
      message  = instance_double(RubyLLM::Message, content: "done")
      instance = instance_double(RubyLLM::Chat, ask: message)
      expect(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      expect(instance).to receive(:ask).with("go")

      expect(agent_class.call("go")).to eq("done")
    end

    it "uses the default message when nil is passed (frai exec without INPUT)" do
      message  = instance_double(RubyLLM::Message, content: "done")
      instance = instance_double(RubyLLM::Chat, ask: message)
      expect(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      expect(instance).to receive(:ask).with("Complete the task.")

      expect(agent_class.call(nil)).to eq("done")
    end

    it "uses the default message when message is whitespace only" do
      message  = instance_double(RubyLLM::Message, content: "done")
      instance = instance_double(RubyLLM::Chat, ask: message)
      expect(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      expect(instance).to receive(:ask).with("Complete the task.")

      expect(agent_class.call("   ")).to eq("done")
    end

    it "raises when LLM_MODEL is missing" do
      Frai.configuration.model = nil

      expect { agent_class.call("go") }
        .to raise_error(Frai::Error, /LLM_MODEL is required for agents/)
    end
  end

  describe ".call in dry run" do
    before do
      Frai.configure do |c|
        c.project_root = project_root
        c.env          = :development
        c.model        = nil
      end
    end

    it "returns dry-run label with default message when INPUT is omitted" do
      expect(agent_class.call).to eq("[dry run] DemoAgent: Complete the task.")
    end

    it "returns dry-run label with default message when nil is passed" do
      expect(agent_class.call(nil)).to eq("[dry run] DemoAgent: Complete the task.")
    end
  end
end
