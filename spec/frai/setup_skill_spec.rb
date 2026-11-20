# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Frai::Setup::Skill do
  # Plain stand-in for a task class. Subclasses of Frai::Task stay in
  # ObjectSpace and leak into other specs (see StructureChecker), so the
  # skill generator is tested with duck-typed objects instead.
  def task_class_for(folder_name, module_name, params: nil)
    decl = params && Struct.new(:params_declaration).new(Frai::ParamsDeclaration.new)
    params&.each { |kind, pname, type, opts| decl.params_declaration.public_send(kind, pname, type, **opts) }

    Class.new do
      define_singleton_method(:name) { module_name }
      define_singleton_method(:task_name) { folder_name }
      define_singleton_method(:_directive_declaration) { decl }
    end
  end

  describe ".build_entries" do
    it "lists required and optional params with defaults" do
      klass = task_class_for("analyze_item", "AnalyzeItem::Task", params: [
        [:required, :item_id, Integer, {}],
        [:optional, :language, String, { default: "en" }]
      ])

      entry = described_class.build_entries([klass]).first

      expect(entry.name).to eq("analyze_item")
      expect(entry.class_name).to eq("AnalyzeItem::Task")
      expect(entry.required).to eq([{ name: :item_id, type: "Integer", default: nil }])
      expect(entry.optional).to eq([{ name: :language, type: "String", default: "en" }])
    end

    it "handles tasks without params" do
      klass = task_class_for("ping", "Ping::Task")

      entry = described_class.build_entries([klass]).first

      expect(entry.required).to eq([])
      expect(entry.optional).to eq([])
    end
  end

  describe ".sync!" do
    it "writes SKILL.md into the host app and bin/frai into the Frai project" do
      Dir.mktmpdir do |host|
        project = File.join(host, "ai")
        FileUtils.mkdir_p(project)
        klass = task_class_for("ping", "Ping::Task")

        path = described_class.sync!(
          project_root: project,
          skill_dir:    "../.claude/skills/ai-tasks",
          task_classes: [klass],
          output:       StringIO.new
        )

        expect(path).to eq(File.join(host, ".claude", "skills", "ai-tasks", "SKILL.md"))
        content = File.read(path)
        frontmatter = YAML.safe_load(content[/\A---\n(.*?)\n---/m, 1])
        expect(frontmatter["name"]).to eq("ai-tasks")
        expect(frontmatter["description"]).to include("ping")
        expect(content).to include("ai/bin/frai exec Ping::Task")
        expect(File.executable?(File.join(project, "bin", "frai"))).to be(true)
      end
    end
  end
end
