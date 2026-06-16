# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Frai::TaskReturnKeys do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      Frai.configure { |c| c.project_root = root }
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
    end
  end

  it "collects return keys from the task schema" do
    expect(described_class.collect(task_class)).to eq([:report])
  end

  it "collects return keys from directive ERB templates" do
    dir = File.join(@root, "tasks", "build_report", "directives")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "task.md.erb"), "% run(:report, params: :data, return: :report)\n")

    stub_const("BuildReport::Task", task_class)
    expect(described_class.collect(task_class)).to eq([:report])
  end
end
