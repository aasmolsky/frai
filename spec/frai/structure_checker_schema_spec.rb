# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Frai::StructureChecker do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      Frai.configure { |c| c.project_root = root }
      example.run
    end
  end

  def write_file(path)
    full_path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, "")
  end

  it "raises MissingOutput when schema is not declared" do
    task_class = Class.new(Frai::Task) do
      def self.task_name; "task_without_schema"; end
    end

    expect {
      described_class.new(task_class).check!
    }.to raise_error(Frai::MissingOutput, /must declare an output type/)
  end

  it "does not raise when output is declared and task.md.erb exists" do
    task_class = Class.new(Frai::Task) do
      def self.task_name; "task_with_schema"; end
      schema { output :text }
    end

    write_file("tasks/task_with_schema/directives/task.md.erb")

    expect {
      described_class.new(task_class).check!
    }.not_to raise_error
  end
end
