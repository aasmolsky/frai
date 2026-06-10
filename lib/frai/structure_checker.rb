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

    # Raises on the first missing file or MCP misconfiguration.
    def check!
      unless @task_class._output_kind
        raise Frai::MissingOutput,
              "#{@task_class} must declare an output type using `schema do ... output :text end`"
      end

      decl = @task_class._directive_declaration
      return unless decl

      find_directive!(:main)
      check_declaration!(decl)
      check_mcp_declarations!
      check_orphan_files!(decl)
    end

    # Validates declared MCPs have corresponding mcp/*.rb definitions,
    # and that all defined mcp/*.rb files are used by at least one task.
    def self.check_mcp_consistency!(project_root)
      # All defined MCP files
      defined = Dir.glob(File.join(project_root, "mcp", "*.rb"))
                   .map { |f| File.basename(f, ".rb").to_sym }

      return if defined.empty?

      # All MCPs declared across all tasks
      declared = ObjectSpace.each_object(Class)
                            .select { |k| k < Frai::Task && k.name && k.superclass != Frai::Task }
                            .flat_map(&:_mcps)
                            .map(&:to_sym)
                            .uniq

      defined.each do |name|
        unless declared.include?(name)
          raise Frai::Error,
            "mcp/#{name}.rb is defined but never declared in any task.\n" \
            "Add `mcp :#{name}` to the task that uses it, or remove the file."
        end
      end
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

    def check_mcp_declarations!
      @task_class._mcps.each do |name|
        path = File.join(@project_root, "mcp", "#{name}.rb")
        next if File.exist?(path)

        raise Frai::Error,
          "Task #{@task_class} declares `mcp :#{name}` but mcp/#{name}.rb does not exist.\n" \
          "Create the file or remove the declaration."
      end
    end

    def check_orphan_files!(decl)
      directives_dir = File.join(@project_root, "tasks", @task_name, "directives")
      if Dir.exist?(directives_dir)
        Dir.glob(File.join(directives_dir, "*.{md.erb,erb}")).each do |file|
          name = File.basename(file).sub(/\.md\.erb$/, "").sub(/\.erb$/, "").to_sym
          next if name == :main
          unless decl.all_directive_names.include?(name)
            raise Frai::Error,
              "Directive `#{name}` exists in #{directives_dir} but is not declared in #{@task_class} schema.\n" \
              "Add `use :#{name}` inside `schema do` or delete the file."
          end
        end
      end

      scripts_dir = File.join(@project_root, "tasks", @task_name, "scripts")
      if Dir.exist?(scripts_dir)
        Dir.glob(File.join(scripts_dir, "*")).each do |file|
          next if File.directory?(file)
          name = File.basename(file, File.extname(file)).to_sym
          unless decl.all_script_names.include?(name)
            raise Frai::Error,
              "Script `#{name}` exists in #{scripts_dir} but is not declared in #{@task_class} schema.\n" \
              "Add `run :#{name}` inside `schema do` or if it's a helper script move it to a separate subfolder (e.g. `scripts/services/`)."
          end
        end
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
