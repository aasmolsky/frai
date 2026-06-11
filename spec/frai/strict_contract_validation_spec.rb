# frozen_string_literal: true
require "tmpdir"
require "spec_helper"
require "frai"
RSpec.describe "Strict Contract Validation: use and run" do
  let(:project_root) { Dir.mktmpdir }
  before do
    allow(Frai.configuration).to receive(:project_root).and_return(project_root)
    FileUtils.mkdir_p(File.join(project_root, "tasks", "test_task", "directives"))
    FileUtils.mkdir_p(File.join(project_root, "tasks", "test_task", "scripts"))
  end
  after do
    FileUtils.remove_entry(project_root)
  end
  context "when sub-directive is not declared in schema" do
    it "raises Frai::UndeclaredDirective" do
      File.write(File.join(project_root, "tasks", "test_task", "directives", "task.md.erb"), "<%= use(:undeclared_sub) %>")
      class TestTaskDirectives < Frai::Task
        def self.task_name; "test_task"; end
        schema { output :text }
      end
      allow(Frai::StructureChecker).to receive(:new).and_return(double(check!: true))
      allow_any_instance_of(Frai::DirectiveRenderer).to receive(:find_directive!).with(:task).and_return(File.join(project_root, "tasks", "test_task", "directives", "task.md.erb"))
      expect { TestTaskDirectives.call }.to raise_error(Frai::UndeclaredDirective, /Cannot use\(:undeclared_sub\) because it is not declared/)
    end
  end
  context "when script is not declared in schema" do
    it "raises Frai::UndeclaredScript" do
      File.write(File.join(project_root, "tasks", "test_task", "directives", "task.md.erb"), "<% run(:undeclared_script) %>")
      class TestTaskScripts < Frai::Task
        def self.task_name; "test_task"; end
        schema { output :text }
      end
      allow(Frai::StructureChecker).to receive(:new).and_return(double(check!: true))
      allow_any_instance_of(Frai::DirectiveRenderer).to receive(:find_directive!).with(:task).and_return(File.join(project_root, "tasks", "test_task", "directives", "task.md.erb"))
      expect { TestTaskScripts.call }.to raise_error(Frai::UndeclaredScript, /Cannot run\(:undeclared_script\) because it is not declared/)
    end
  end
end
