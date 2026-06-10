# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "ruby_llm/schema"

RSpec.describe "Task structured output with retries" do
  after { Frai.reset! }

  let(:adapter_responses) { [] }
  let(:received_schemas) { [] }
  let(:fake_adapter) do
    schemas = received_schemas
    responses = adapter_responses

    Class.new do
      define_method(:complete) do |_prompt, mcp_servers: [], schema: nil|
        raise "unexpected MCP call" unless mcp_servers.empty?

        schemas << schema
        responses.shift || raise("no more stubbed responses")
      end
    end.new
  end

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "score_reviews", "directives"))
      File.write(File.join(root, "tasks", "score_reviews", "directives", "main.md.erb"), "Score reviews")

      File.write(
        File.join(root, "tasks", "score_reviews", "task.rb"),
        <<~RUBY
          require "ruby_llm/schema"

          module ScoreReviews
            class OutputSchema < RubyLLM::Schema
              array :processed_reviews do
                object do
                  string :review_id
                end
              end
            end

            class Task < BaseTask
              schema do
                param :reviews, type: Array, required: true

                output OutputSchema, retries: 1 do |data, params|
                  expected = Array(params[:reviews]).size
                  actual   = Array(data[:processed_reviews]).size
                  raise Frai::ValidationError, "expected \#{expected} reviews, got \#{actual}" if expected != actual
                end
              end
            end
          end
        RUBY
      )

      load File.join(root, "tasks", "score_reviews", "task.rb")

      Frai.configure do |config|
        config.project_root = root
        config.env          = :production
        config.model        = "claude-opus-4-6"
        config.api_key      = "test-key"
      end

      example.run
    end
  end

  it "passes RubyLLM::Schema to the adapter and returns a Hash", :aggregate_failures do
    adapter_responses.replace([{ "processed_reviews" => [{ "review_id" => "1" }] }])

    task = ScoreReviews::Task.new
    allow(task).to receive(:adapter).and_return(fake_adapter)

    result = task.call(reviews: [{ review_id: "1" }])

    expect(received_schemas).to eq([ScoreReviews::OutputSchema])
    expect(result).to eq(processed_reviews: [{ review_id: "1" }])
  end

  it "retries once when validation fails and then succeeds", :aggregate_failures do
    adapter_responses.replace(
      [
        { "processed_reviews" => [] },
        { "processed_reviews" => [{ "review_id" => "1" }] }
      ]
    )

    task = ScoreReviews::Task.new
    allow(task).to receive(:adapter).and_return(fake_adapter)

    result = task.call(reviews: [{ review_id: "1" }])

    expect(result).to eq(processed_reviews: [{ review_id: "1" }])
    expect(adapter_responses).to be_empty
    expect(received_schemas.size).to eq(2)
  end

  it "raises OutputRetriesExhaustedError after retries are exhausted", :aggregate_failures do
    adapter_responses.replace(
      [
        { "processed_reviews" => [] },
        { "processed_reviews" => [] }
      ]
    )

    task = ScoreReviews::Task.new
    allow(task).to receive(:adapter).and_return(fake_adapter)

    error = nil
    begin
      task.call(reviews: [{ review_id: "1" }])
    rescue Frai::OutputRetriesExhaustedError => e
      error = e
    end

    expect(error).to be_a(Frai::OutputRetriesExhaustedError)
    expect(error.message).to match(/Output failed after 2 attempts/)
    expect(error.last_error).to be_a(Frai::ValidationError)
    expect(error.attempts).to eq(2)
    expect(error.task_class).to eq(ScoreReviews::Task)
  end
end
