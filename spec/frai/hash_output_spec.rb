# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Task output Hash" do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "build_report", "directives"))
      FileUtils.mkdir_p(File.join(root, "tasks", "build_report", "scripts"))

      # Directive renders script result as JSON
      File.write(
        File.join(root, "tasks", "build_report", "directives", "main.md.erb"),
        "% run(:report, params: :data, return: :report)\n<%= report.to_json %>"
      )

      # Script echoes input back as report
      File.write(
        File.join(root, "tasks", "build_report", "scripts", "report.rb"),
        <<~RUBY
          #!/usr/bin/env ruby
          require "json"
          payload = JSON.parse($stdin.read, symbolize_names: true)
          data = payload[:input] || payload
          puts JSON.generate(report: { title: data[:title], count: data[:count] })
        RUBY
      )

      File.write(
        File.join(root, "tasks", "build_report", "task.rb"),
        <<~RUBY
          module BuildReport
            class Task < BaseTask
              schema do
                llm false

                param :data, type: Hash, required: true do
                  required(:title).filled(:string)
                  required(:count).filled(:integer)
                end

                run :report do
                  input type: Hash do
                    required(:title).filled(:string)
                    required(:count).filled(:integer)
                  end
                  returns :report, type: Hash do
                    required(:title).filled(:string)
                    required(:count).filled(:integer)
                  end
                end

                output Hash
              end
            end
          end
        RUBY
      )

      load File.join(root, "tasks", "build_report", "task.rb")

      Frai.configure do |config|
        config.project_root = root
        config.env          = :test
      end

      example.run
    end
  end

  it "returns a Hash directly (no JSON.parse needed)", :aggregate_failures do
    result = BuildReport::Task.call(data: { title: "Test", count: 5 })

    expect(result).to be_a(Hash)
    expect(result[:title]).to eq("Test")
    expect(result[:count]).to eq(5)
  end

  it "returns Hash in production env too", :aggregate_failures do
    Frai.configure { |c| c.env = :production }

    result = BuildReport::Task.call(data: { title: "Prod", count: 3 })

    expect(result).to be_a(Hash)
    expect(result[:title]).to eq("Prod")
  end
end

RSpec.describe "Mandatory output — error message includes Hash" do
  after { Frai.reset! }

  it "suggests output Hash in MissingOutput message" do
    expect do
      Class.new(Frai::Task) do
        def self.name = "NoOutput::Task"

        schema do
          param :id, type: String, required: true
        end
      end
    end.to raise_error(Frai::MissingOutput, /output Hash/)
  end
end
