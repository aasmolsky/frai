# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "ScriptTool returns integration" do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      Frai.configure do |c|
        c.project_root = root
        c.env          = :test
      end
      example.run
    end
  end

  let(:task_class) do
    Class.new(Frai::Task) do
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

      def call(*)
        @_script_results = { report: { status: "ok" } }
        { status: "ok" }
      end

      def script_results
        @_script_results
      end

      def prompt_results
        { prompt: "" }
      end
    end
  end

  let(:tool_class) do
    task = task_class
    Class.new(Frai::ScriptTool) do
      define_singleton_method(:name) { "BuildReportTool" }
      task task
      returns :report

      def execute
        call_task
      end
    end
  end

  it "stores script_results return key in AgentReturnStore after call_task" do
    Frai::AgentReturnStore.with_store do
      tool_class.new.execute
      expect(Frai::AgentReturnStore.value).to eq(status: "ok")
    end
  end

  describe "Agent.run" do
    let(:agent_class) do
      tool = tool_class
      Class.new(Frai::Agent) do
        define_singleton_method(:name) { "ReportAgent" }
        instructions "Run the report tool."
        tools { [tool.new] }
      end
    end

    before do
      Frai.configure do |c|
        c.env     = :production
        c.model   = "gpt-4o"
        c.api_key = "test-key"
      end
    end

    it "returns script result through Agent.run without mocking AgentReturnStore" do
      message  = instance_double(RubyLLM::Message, content: "ignored")
      instance = agent_class.new(model: "gpt-4o")
      allow(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      allow(instance).to receive(:ask) do
        tool_class.new.execute
        message
      end

      result = agent_class.run("go")

      expect(result.result).to eq(status: "ok")
      expect(result.output).to eq(status: "ok")
      expect(result.message).to eq("ignored")
    end

    it "raises when a returns tool exists but was not invoked" do
      message  = instance_double(RubyLLM::Message, content: "done without tool")
      instance = agent_class.new(model: "gpt-4o")
      allow(agent_class).to receive(:new).with(model: "gpt-4o").and_return(instance)
      allow(instance).to receive(:ask).and_return(message)

      expect { agent_class.run("go") }
        .to raise_error(Frai::Error, /expected a script return/)
    end
  end
end
