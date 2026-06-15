# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Task#script_results" do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "analyze_data", "directives"))
      FileUtils.mkdir_p(File.join(root, "tasks", "analyze_data", "scripts"))

      # Directive calls the script and uses its output
      File.write(
        File.join(root, "tasks", "analyze_data", "directives", "task.md.erb"),
        "% run(:prepare, params: :payload, return: :prepared)\n"
      )

      # Script returns { prepared: { value: ..., doubled: ... } }
      File.write(
        File.join(root, "tasks", "analyze_data", "scripts", "prepare.rb"),
        <<~RUBY
          def call(input)
            { prepared: { value: input[:value], doubled: input[:value].to_i * 2 } }
          end
        RUBY
      )

      File.write(
        File.join(root, "tasks", "analyze_data", "task.rb"),
        <<~RUBY
          module AnalyzeData
            class Task < BaseTask
              schema do
                llm false

                param :payload, type: Hash, required: true do
                  required(:value).filled(:integer)
                end

                directive :task do
                  run :prepare do
                    input type: Hash do
                      required(:value).filled(:integer)
                    end
                  end
                end

                output Hash
              end

              def call(input)
                result = super
                [script_results[:prepared], result]
              end
            end
          end
        RUBY
      )

      load File.join(root, "tasks", "analyze_data", "task.rb")

      Frai.configure do |config|
        config.project_root = root
        config.env          = :test
      end

      example.run
    end
  end

  it "returns script output keyed by return: key after super" do
    result = AnalyzeData::Task.call(payload: { value: 5 })

    expect(result).to be_a(Array)
    script_data, llm_result = result
    expect(script_data).to eq({ value: 5, doubled: 10 })
    expect(llm_result).to be_a(Hash)
  end

  it "script_results is empty on a fresh instance before call" do
    task = AnalyzeData::Task.new
    expect(task.script_results).to eq({})
  end

  it "script_results is isolated per call — no leakage between calls" do
    result1 = AnalyzeData::Task.call(payload: { value: 2 })
    result2 = AnalyzeData::Task.call(payload: { value: 7 })

    expect(result1[0]).to eq({ value: 2, doubled: 4 })
    expect(result2[0]).to eq({ value: 7, doubled: 14 })
  end
end

RSpec.describe "ScriptRunner#return_values" do
  let(:runner) { Frai::ScriptRunner.new("my_task", "/tmp") }

  it "starts empty" do
    expect(runner.return_values).to eq({})
  end

  it "stores values via store_return" do
    runner.store_return(:prepared, { value: 5, doubled: 10 })
    expect(runner.return_values).to eq({ prepared: { value: 5, doubled: 10 } })
  end

  it "coerces key to symbol" do
    runner.store_return("my_key", "data")
    expect(runner.return_values).to have_key(:my_key)
  end

  it "accumulates multiple keys" do
    runner.store_return(:first, 1)
    runner.store_return(:second, 2)
    expect(runner.return_values).to eq({ first: 1, second: 2 })
  end
end
