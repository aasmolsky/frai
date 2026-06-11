# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Task text output" do
  after { Frai.reset! }

  let(:adapter_responses) { [] }
  let(:fake_adapter) do
    responses = adapter_responses

    Class.new do
      define_method(:complete) do |_prompt, mcp_servers: [], schema: nil|
        raise "unexpected schema" unless schema.nil?
        raise "unexpected MCP call" unless mcp_servers.empty?

        responses.shift || raise("no more stubbed responses")
      end
    end.new
  end

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "summarize", "directives"))
      File.write(File.join(root, "tasks", "summarize", "directives", "task.md.erb"), "Summarize")

      File.write(
        File.join(root, "tasks", "summarize", "task.rb"),
        <<~RUBY
          module Summarize
            class Task < BaseTask
              schema do
                param :text, type: String, required: true

                output :text, retries: 1 do |response, params|
                  if response.to_s.strip.empty?
                    raise Frai::ValidationError, "response must not be empty"
                  end

                  unless response.include?(params[:text])
                    raise Frai::ValidationError, "response must mention input text"
                  end
                end
              end
            end
          end
        RUBY
      )

      load File.join(root, "tasks", "summarize", "task.rb")

      Frai.configure do |config|
        config.project_root = root
        config.env          = :production
        config.model        = "claude-opus-4-6"
        config.api_key      = "test-key"
      end

      example.run
    end
  end

  it "returns a String from the adapter", :aggregate_failures do
    adapter_responses.replace(["Summary of hello world"])

    task = Summarize::Task.new
    allow(task).to receive(:adapter).and_return(fake_adapter)

    result = task.call(text: "hello world")

    expect(result).to eq("Summary of hello world")
  end

  it "retries when text validation fails", :aggregate_failures do
    adapter_responses.replace(["too short", "Summary of hello world"])

    task = Summarize::Task.new
    allow(task).to receive(:adapter).and_return(fake_adapter)

    result = task.call(text: "hello world")

    expect(result).to eq("Summary of hello world")
    expect(adapter_responses).to be_empty
  end
end

RSpec.describe "Mandatory output declaration" do
  after { Frai.reset! }

  it "raises MissingOutput when llm is enabled without output" do
    expect do
      Class.new(Frai::Task) do
        def self.name = "Broken::Task"

        schema do
          param :id, type: String, required: true
        end
      end
    end.to raise_error(Frai::MissingOutput, /must declare output/)
  end

  it "requires output even when llm is false" do
    expect do
      Class.new(Frai::Task) do
        def self.name = "PromptOnly::Task"

        schema do
          llm false
          param :id, type: String, required: true
        end
      end
    end.to raise_error(Frai::MissingOutput, /must declare output/)
  end

  it "accepts llm false with output :text" do
    task_class = Class.new(Frai::Task) do
      def self.name = "PromptOnly::Task"

      schema do
        llm false
        param :id, type: String, required: true

        output :text
      end
    end

    expect(task_class._output_kind).to eq(:text)
    expect(task_class._llm_enabled).to be(false)
  end
end
