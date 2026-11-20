# frozen_string_literal: true

require "erb"
require "json"
require "fileutils"
require "pathname"

module Frai
  module Setup
    # Generates a Claude Code skill (SKILL.md) for the tasks of a Frai project
    # that lives in a subfolder of a host application (e.g. Rails).
    #
    # The skill is written into the host app's `.claude/skills/<name>/`, so an
    # agent started in the host app root can discover it. Commands in the skill
    # go through `bin/frai` in the Frai project, which isolates Ruby and gems.
    module Skill
      module_function

      TASK_SKILL_TEMPLATE = File.expand_path("../generators/templates/skill/SKILL.md.erb", __dir__)
      WRAPPER_TEMPLATE    = File.expand_path("../generators/templates/bin/frai.erb", __dir__)

      TaskEntry = Struct.new(:name, :class_name, :required, :optional, keyword_init: true)

      # @param project_root [String] Frai project directory (contains tasks/, config/)
      # @param skill_dir [String]    e.g. "../.claude/skills/ai-tasks" (relative to project_root)
      # @param task_classes [Array<Class>]
      # @return [String] path of the written SKILL.md
      def sync!(project_root:, skill_dir:, task_classes:, output: $stdout)
        project_root = File.expand_path(project_root)
        skill_path   = File.expand_path(skill_dir, project_root)
        host_root    = skill_root_for(skill_path)

        wrapper = ensure_wrapper!(project_root, output: output)
        tasks   = build_entries(task_classes)
        wrapper_path = relative_wrapper_path(wrapper, host_root)

        FileUtils.mkdir_p(skill_path)
        skill_file = File.join(skill_path, "SKILL.md")
        content    = render(skill_name: File.basename(skill_path), tasks: tasks, wrapper_path: wrapper_path)
        existed    = File.exist?(skill_file)
        File.write(skill_file, content)

        output.puts "  \e[32m#{existed ? 'update' : 'create'}\e[0m  #{skill_file}"
        skill_file
      end

      # @return [Array<TaskEntry>]
      def build_entries(task_classes)
        task_classes.map do |klass|
          decl   = klass._directive_declaration&.params_declaration
          params = decl ? decl.required_params.map { |n, t| param_hash(n, t) } : []
          opt    = decl ? decl.optional_params.map { |n, o| param_hash(n, o[:type], o[:default]) } : []

          TaskEntry.new(
            name:       klass.task_name,
            class_name: klass.name,
            required:   params,
            optional:   opt
          )
        end.sort_by(&:name)
      end

      def param_hash(name, type, default = nil)
        { name: name, type: type_label(type), default: default }
      end

      def type_label(type)
        type.respond_to?(:name) ? type.name : type.to_s
      end

      def render(skill_name:, tasks:, wrapper_path:)
        description = "Run Frai LLM tasks of this app (#{tasks.size} task#{'s' unless tasks.size == 1}). " \
                      "Use when the user asks to run one of these tasks: #{tasks.map(&:name).join(', ')}."
        ERB.new(File.read(TASK_SKILL_TEMPLATE), trim_mode: "-").result(binding)
      end

      # Writes bin/frai into the Frai project if it is missing.
      def ensure_wrapper!(project_root, output: $stdout)
        bin_dir = File.join(project_root, "bin")
        path    = File.join(bin_dir, "frai")
        return path if File.exist?(path)

        FileUtils.mkdir_p(bin_dir)
        File.write(path, File.read(WRAPPER_TEMPLATE))
        File.chmod(0o755, path)
        output.puts "  \e[32mcreate\e[0m  #{path}"
        path
      end

      # The host app root is assumed to be the parent of `.claude/skills/<name>`.
      def skill_root_for(skill_path)
        File.expand_path("../../..", skill_path)
      end

      # Path to the wrapper as seen from the host app root (where the agent runs).
      def relative_wrapper_path(wrapper, host_root)
        Pathname.new(wrapper).relative_path_from(Pathname.new(host_root)).to_s
      end
    end
  end
end
