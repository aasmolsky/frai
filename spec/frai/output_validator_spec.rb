# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "ruby_llm/schema"

RSpec.describe "Task output validation on instance" do
  after { Frai.reset! }

  let(:adapter_responses) { [] }
  let(:fake_adapter) do
    responses = adapter_responses

    Class.new do
      define_method(:complete) do |_prompt, mcp_servers: [], schema: nil|
        raise "unexpected MCP call" unless mcp_servers.empty?

        responses.shift || raise("no more stubbed responses")
      end
    end.new
  end

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "score_reviews", "directives"))
      File.write(File.join(root, "tasks", "score_reviews", "directives", "main.md.erb"), "Score reviews")

      Frai.configure do |config|
        config.project_root = root
        config.env          = :production
        config.model        = "claude-opus-4-6"
        config.api_key      = "test-key"
      end

      example.run
    end
  end

  context "with validate: method name" do
    before do
      write_task(<<~RUBY)
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

              output OutputSchema, validate: :validate_response!, retries: 0
            end

            private

            def validate_response!(output, input)
              expected = Array(input[:reviews]).size
              actual   = Array(output[:processed_reviews]).size
              return if expected == actual

              raise Frai::ValidationError, "expected \#{expected} reviews, got \#{actual}"
            end
          end
        end
      RUBY
    end

    it "calls a private instance method" do
      adapter_responses.replace([{ "processed_reviews" => [{ "review_id" => "1" }] }])

      task = ScoreReviews::Task.new
      allow(task).to receive(:adapter).and_return(fake_adapter)

      result = task.call(reviews: [{ review_id: "1" }])

      expect(result).to eq(processed_reviews: [{ review_id: "1" }])
    end
  end

  context "with a block delegating to a private instance method" do
    before do
      write_task(<<~RUBY)
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

              output OutputSchema, retries: 0 do |output, input|
                validate_response!(output, input)
              end
            end

            private

            def validate_response!(output, input)
              expected = Array(input[:reviews]).size
              actual   = Array(output[:processed_reviews]).size
              return if expected == actual

              raise Frai::ValidationError, "expected \#{expected} reviews, got \#{actual}"
            end
          end
        end
      RUBY
    end

    it "runs the block on the task instance" do
      adapter_responses.replace([{ "processed_reviews" => [{ "review_id" => "1" }] }])

      task = ScoreReviews::Task.new
      allow(task).to receive(:adapter).and_return(fake_adapter)

      result = task.call(reviews: [{ review_id: "1" }])

      expect(result).to eq(processed_reviews: [{ review_id: "1" }])
    end
  end

  def write_task(source)
    path = File.join(Frai.configuration.project_root, "tasks", "score_reviews", "task.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    load path
  end
end
