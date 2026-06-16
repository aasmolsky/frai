# frozen_string_literal: true

require "spec_helper"
require "dry/schema"

RSpec.describe Frai::TaskTool do
  let(:input_schema) do
    Dry::Schema.define do
      required(:processed_reviews).filled(:array)
    end
  end

  let(:task_class) do
    schema = input_schema
    Class.new(Frai::Task) do
      define_singleton_method(:name) { "PrepareData::Task" }

      schema do
        llm false
        output Hash

        param :llm_data, type: Hash, validate: schema

        directive :task do
          run :prepare do
            returns :report_input, type: Hash do
              required(:status).filled(:string)
            end
          end
        end
      end

      def call(input = nil)
        validate_params!(self.class._directive_declaration, input)
        @_script_results = { report_input: { status: "ok" } }
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
      define_singleton_method(:name) { "PrepareDataTool" }

      task task

      def execute(llm_data:)
        call_task(llm_data: llm_data)
      end
    end
  end

  after { Frai.reset! }

  describe "#call" do
    it "deep-symbolizes string keys in LLM tool arguments before execute" do
      tool = tool_class.new

      result = tool.call("llm_data" => { "processed_reviews" => [{ "review_id" => "r1" }] })

      expect(result[:report_input]).to eq(status: "ok")
    end
  end

  describe "#call_task" do
    it "deep-symbolizes params assembled from constructor state" do
      tool = tool_class.new(
        "language" => "en",
        "place_data" => { "title" => "Test", "rating" => 4.5, "reviews_count" => 1, "address" => "St" }
      )

      expect(tool.state[:language]).to eq("en")
      expect(tool.state[:place_data][:title]).to eq("Test")
    end
  end

  describe "#normalize_param" do
    let(:custom_tool_class) do
      task = task_class
      Class.new(Frai::ScriptTool) do
        define_singleton_method(:name) { "CustomTool" }
        task task

        def normalize_param(name, value)
          value = super
          return value[:report_input] if name == :llm_data && value.is_a?(Hash) && value.key?(:report_input)

          value
        end

        def execute(llm_data:)
          call_task(llm_data: llm_data)
        end
      end
    end

    it "allows subclasses to unwrap envelopes after symbolization" do
      tool = custom_tool_class.new

      result = tool.call("llm_data" => { "report_input" => { "processed_reviews" => [{ "review_id" => "r1" }] } })

      expect(result[:report_input]).to eq(status: "ok")
    end
  end

  describe "inheritance" do
    it "keeps PromptTool and ScriptTool as TaskTool subclasses" do
      expect(Frai::PromptTool).to be < described_class
      expect(Frai::ScriptTool).to be < described_class
    end
  end
end
