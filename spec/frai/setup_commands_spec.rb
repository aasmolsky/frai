# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Frai::Setup::Commands do
  let(:template_path) do
    File.expand_path("../../lib/frai/generators/templates/commands/task.md.erb", __dir__)
  end

  def task_class_for(folder_name, module_name)
    Class.new(Frai::Task) do
      define_singleton_method(:name) { module_name }
      define_singleton_method(:task_name) { folder_name }
    end
  end

  describe ".qualified_class_name" do
    it "uses the loaded task class name, not naive capitalize" do
      klass = task_class_for("prepare_llm_report", "PrepareLLMReport::Task")

      expect(described_class.qualified_class_name("prepare_llm_report", [klass]))
        .to eq("PrepareLLMReport::Task")
    end

    it "falls back to folder-based name when class is not loaded" do
      expect(described_class.qualified_class_name("analyze_item", []))
        .to eq("AnalyzeItem::Task")
    end
  end

  describe ".sync!" do
    it "updates an existing slash command when class name differs" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "tasks", "prepare_llm_report"))
        File.write(File.join(root, "tasks", "prepare_llm_report", "task.rb"), "# task")

        commands_dir = File.join(root, ".claude", "commands")
        FileUtils.mkdir_p(commands_dir)
        File.write(
          File.join(commands_dir, "prepare_llm_report.md"),
          described_class.render_command(
            template_path,
            name: "prepare_llm_report",
            qualified_class_name: "PrepareLlmReport::Task"
          )
        )

        klass = task_class_for("prepare_llm_report", "PrepareLLMReport::Task")
        counts = described_class.sync!(
          root: root,
          task_classes: [klass],
          template_path: template_path,
          output: StringIO.new
        )

        content = File.read(File.join(commands_dir, "prepare_llm_report.md"))
        expect(content).to include("frai exec PrepareLLMReport::Task")
        expect(content).not_to include("PrepareLlmReport::Task")
        expect(counts[:updated]).to eq(1)
      end
    end

    it "creates a new slash command with the resolved class name" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "tasks", "prepare_llm_report"))
        File.write(File.join(root, "tasks", "prepare_llm_report", "task.rb"), "# task")

        klass = task_class_for("prepare_llm_report", "PrepareLLMReport::Task")
        counts = described_class.sync!(
          root: root,
          task_classes: [klass],
          template_path: template_path,
          output: StringIO.new
        )

        path = File.join(root, ".claude", "commands", "prepare_llm_report.md")
        expect(File).to exist(path)
        expect(File.read(path)).to include("frai exec PrepareLLMReport::Task")
        expect(counts[:created]).to eq(1)
      end
    end
  end
end
