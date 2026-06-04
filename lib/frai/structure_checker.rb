module Frai
  # Validates that all files declared in a task's directive scheme
  # actually exist on disk. Runs before any LLM call.
  #
  # Checks:
  #   - directives/<name>.md.erb exists (local or global)
  #   - scripts/<name>.* exists (local or global)
  #   - mcp/<name>.rb exists and the server is registered
  class StructureChecker
    # @param task_class [Class] the task class to validate
    def initialize(task_class)
      @task_class   = task_class
      @task_name    = task_class.task_name
      @project_root = Frai.configuration.project_root
    end

    # Runs all structure checks. Raises on first violation.
    def check!
      return unless @task_class._directive_declaration

      decl = @task_class._directive_declaration

      check_mcps!(decl)
      check_main_directive!
      check_used_directives!(decl)
      check_scripts!(decl)
    end

    private

    # main.md.erb must always exist
    def check_main_directive!
      path = find_directive(@task_class._directive_declaration.name)
      unless path
        raise Frai::MissingDirective,
          "main directive not found for #{@task_class}.\n" \
          "Expected: tasks/#{@task_name}/directives/main.md.erb"
      end
    end

    def check_used_directives!(decl)
      decl.all_directives.each do |name|
        unless find_directive(name)
          raise Frai::MissingDirective,
            "declared 'uses :#{name}' in #{@task_class} but directive file not found.\n" \
            "Expected: tasks/#{@task_name}/directives/#{name}.md.erb\n" \
            "      or: directives/#{name}.md.erb"
        end
      end
    end

    def check_scripts!(decl)
      decl.all_scripts.each do |name|
        unless find_script(name)
          raise Frai::MissingScript,
            "declared 'runs :#{name}' in #{@task_class} but script file not found.\n" \
            "Expected: tasks/#{@task_name}/scripts/#{name}.*\n" \
            "      or: scripts/#{name}.*"
        end
      end
    end

    # Checks that each declared MCP server:
    #   1. Has a definition file in mcp/<name>.rb
    #   2. Is registered via Frai::MCP.define (i.e. the file was loaded)
    def check_mcps!(decl)
      decl.all_mcps.each do |name|
        file = File.join(@project_root, "mcp", "#{name}.rb")

        unless File.exist?(file)
          raise Frai::MissingMCP,
            "declared 'mcp :#{name}' in #{@task_class} but mcp/#{name}.rb not found.\n" \
            "Generate it with: frai generate mcp #{name}"
        end

        # Load the file if not already loaded
        require file unless Frai::MCP.find(name)

        unless Frai::MCP.find(name)
          raise Frai::MissingMCP,
            "mcp/#{name}.rb exists but does not define Frai::MCP.define :#{name}.\n" \
            "Make sure the file calls Frai::MCP.define :#{name} do ... end"
        end
      end
    end

    # Looks for directive file: local first, then global
    def find_directive(name)
      local  = File.join(@project_root, "tasks", @task_name, "directives", "#{name}.md.erb")
      global = File.join(@project_root, "directives", "#{name}.md.erb")
      File.exist?(local) ? local : (File.exist?(global) ? global : nil)
    end

    # Looks for script file by name with any extension: local first, then global
    def find_script(name)
      local_pattern  = File.join(@project_root, "tasks", @task_name, "scripts", "#{name}.*")
      global_pattern = File.join(@project_root, "scripts", "#{name}.*")
      Dir.glob(local_pattern).first || Dir.glob(global_pattern).first
    end
  end
end
