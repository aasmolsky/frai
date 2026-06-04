# frozen_string_literal: true

module Frai
  # Validates that all files declared in a task's directive structure
  # actually exist on disk. Runs before any LLM call.
  class StructureChecker
    def initialize(task_class)
      @task_class   = task_class
      @task_name    = task_class.task_name
      @project_root = Frai.configuration.project_root
    end

    # Raises on the first missing file.
    def check!
      decl = @task_class._directive_declaration
      return unless decl

      find_directive!(:main)
      check_declaration!(decl)
    end

    private

    def check_declaration!(decl)
      decl.sub_directives.each do |name, sub|
        find_directive!(name)
        check_declaration!(sub)
      end

      decl.script_declarations.each_key do |name|
        find_script!(name)
      end
    end

    def find_directive!(name)
      candidates = [
        File.join(@project_root, "tasks", @task_name, "directives", "#{name}.md.erb"),
        File.join(@project_root, "tasks", @task_name, "directives", "#{name}.erb"),
        File.join(@project_root, "directives", "#{name}.md.erb")
      ]

      return if candidates.any? { |p| File.exist?(p) }

      raise Frai::MissingDirective,
        "Directive '#{name}' not found for #{@task_class}.\n" \
        "Expected: tasks/#{@task_name}/directives/#{name}.md.erb"
    end

    def find_script!(name)
      local  = Dir.glob(File.join(@project_root, "tasks", @task_name, "scripts", "#{name}.*")).first
      global = Dir.glob(File.join(@project_root, "scripts", "#{name}.*")).first
      return if local || global

      raise Frai::MissingScript,
        "Script '#{name}' not found for #{@task_class}.\n" \
        "Expected: tasks/#{@task_name}/scripts/#{name}.*"
    end
  end
end
