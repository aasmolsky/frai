# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "frai"

RSpec.describe Frai::StructureChecker do
  let(:project_root) { Dir.mktmpdir }
  before do
    allow(Frai.configuration).to receive(:project_root).and_return(project_root)
  end
  after do
    FileUtils.remove_entry(project_root)
  end
  it "raises MissingOutput if schema is not declared at all" do
    class TaskWithoutSchema < Frai::Task
      def self.task_name; "task_without_schema"; end
    end
    expect {
      Frai::StructureChecker.new(TaskWithoutSchema).check!
    }.to raise_error(Frai::MissingOutput, /must declare an output type/)
  end
  it "does not raise if output is declared" do
    class TaskWithSchema < Frai::Task
      def self.task_name; "task_with_schema"; end
      schema { output :text }
    end
    # Needs a main.md.erb to pass
    FileUtils.mkdir_p(File.join(project_root, "tasks", "task_with_schema", "directives"))
    File.write(File.join(project_root, "tasks", "task_with_schema", "directives", "main.md.erb"), "")
    expect {
      Frai::StructureChecker.new(TaskWithSchema).check!
    }.not_to raise_error
  end
end
