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

    it "returns script result as output when ScriptTool captured one during the run" do
      report = { status: "ok" }

      allow(Frai::AgentReturnStore).to receive(:with_store).and_yield
      allow(Frai::AgentReturnStore).to receive(:value).and_return(report)

      message  = instance_double(RubyLLM::Message, content: "ignored text")
      instance = instance_double(RubyLLM::Chat, ask: message)
      expect(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      expect(instance).to receive(:ask).with("go")

      expect(agent_class.call("go")).to eq(status: "ok")
    end

    it "returns AgentResult from run with result, message, and output" do
      report = { status: "ok" }

      allow(Frai::AgentReturnStore).to receive(:with_store).and_yield
      allow(Frai::AgentReturnStore).to receive(:value).and_return(report)

      message  = instance_double(RubyLLM::Message, content: "ignored text")
      instance = instance_double(RubyLLM::Chat, ask: message)
      expect(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      expect(instance).to receive(:ask).with("go")

      result = agent_class.run("go")

      expect(result).to be_a(Frai::Agent::AgentResult)
      expect(result.output).to eq(status: "ok")
      expect(result.result).to eq(status: "ok")
      expect(result.message).to eq("ignored text")
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

    it "returns dry-run AgentResult from run" do
      result = agent_class.run

      expect(result).to be_a(Frai::Agent::AgentResult)
      expect(result.output).to eq("[dry run] DemoAgent: Complete the task.")
      expect(result.result).to be_nil
      expect(result.message).to eq("[dry run] DemoAgent: Complete the task.")
    end

    it "returns dry-run label with default message when INPUT is omitted" do
      expect(agent_class.call).to eq("[dry run] DemoAgent: Complete the task.")
    end

    it "returns dry-run label with default message when nil is passed" do
      expect(agent_class.call(nil)).to eq("[dry run] DemoAgent: Complete the task.")
    end

    it "runs structure check before dry run and raises on invalid returns setup" do
      task_class = Class.new(Frai::Task) do
        def self.name = "BuildReport::Task"

        schema do
          llm false
          output Hash

          directive :task do
            run :report do
              returns :report, type: Hash do
                required(:status).filled(:string)
              end
            end
          end
        end
      end

      first_tool = Class.new(Frai::ScriptTool) do
        def self.name = "FirstTool"
        task task_class
        returns :report
      end

      second_tool = Class.new(Frai::ScriptTool) do
        def self.name = "SecondTool"
        task task_class
        returns :report
      end

      invalid_agent = Class.new(described_class) do
        def self.name = "InvalidAgent"
        instructions "Do the thing."
        tools { [first_tool.new, second_tool.new] }
      end

      stub_const("InvalidAgent", invalid_agent)
      write_file = lambda do |path|
        full = File.join(project_root, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, "")
      end
      write_file.call("agents/invalid/directives/instructions.md.erb")

      expect { invalid_agent.call("go") }
        .to raise_error(Frai::Error, /multiple ScriptTools/)
    end
  end
end
