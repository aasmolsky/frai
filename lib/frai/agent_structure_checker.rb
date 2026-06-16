# frozen_string_literal: true

module Frai
  # Validates agent instructions contract for all three instructions modes.
  class AgentStructureChecker
    def initialize(agent_class)
      @agent_class  = agent_class
      @agent_name   = agent_class._agent_directive_path
      @project_root = Frai.configuration.project_root
    end

    def check!
      check_returns_tools!

      mode = @agent_class.instructions_mode
      return unless mode

      case mode
      when :inline      then check_unused_directive_files!
      when :file        then check_file_mode!
      when :composite   then check_composite_mode!
      end
    end

    private

    def check_returns_tools!
      returning_tools = AgentToolsResolver.script_tools_with_returns(@agent_class)

      if returning_tools.size > 1
        names = returning_tools.map(&:name).join(", ")
        raise Frai::Error,
          "#{@agent_class} declares `returns` on multiple ScriptTools (#{names}).\n" \
          "Use `returns` on one final tool only."
      end

      returning_tools.each { |tool_class| check_returns_tool!(tool_class) }
    rescue Frai::Error
      raise
    rescue => e
      raise Frai::Error,
        "Could not inspect tools for #{@agent_class}: #{e.message}\n" \
        "Ensure `tools do` works with nil agent inputs (for frai check)."
    end

    def check_returns_tool!(tool_class)
      key = tool_class.returns_key
      task_class = tool_class.task
      unless task_class
        raise Frai::Error,
          "#{tool_class} declares `returns :#{key}` but has no `task`.\n" \
          "Add `task YourTask::Task` to the ScriptTool."
      end

      allowed = TaskReturnKeys.collect(task_class, project_root: @project_root)
      return if allowed.include?(key)

      raise Frai::Error,
        "#{tool_class} declares `returns :#{key}`, but #{task_class} does not declare that return key.\n" \
        "Add `returns :#{key}` (or `return: :#{key}` in a directive) to the task schema."
    end

    def check_file_mode!
      find_directive!(:instructions)
      check_orphan_files!(%i[instructions])
    end

    def check_composite_mode!
      declaration = @agent_class.instructions_declaration
      raise Frai::Error, "#{@agent_class} is missing instructions declaration" unless declaration

      allowed = ([declaration.name] + declaration.all_directive_names).uniq
      allowed.each { |name| find_directive!(name) }
      check_orphan_files!(allowed)
    end

    def check_unused_directive_files!
      files = directive_files_on_disk
      return if files.empty?

      listed = files.map { |path| "- #{path}" }.join("\n")
      raise Frai::Error,
        "Inline instructions in #{@agent_class}, but unused directive files were found:\n" \
        "#{listed}\n" \
        "Remove the files or switch to `instructions` / `instructions do`."
    end

    def check_orphan_files!(allowed_names)
      directive_files_on_disk.each do |path|
        name = directive_basename(path)
        next if allowed_names.include?(name)

        raise Frai::Error,
          "Directive `#{name}` exists in #{directives_dir} but is not declared in #{@agent_class} instructions.\n" \
          "Add `use :#{name}` inside `instructions do` or delete the file."
      end
    end

    def find_directive!(name)
      path = File.join(directives_dir, "#{name}.md.erb")
      return if File.exist?(path)

      raise Frai::MissingDirective,
        "Directive '#{name}' not found for #{@agent_class}.\n" \
        "Expected: agents/#{@agent_name}/directives/#{name}.md.erb"
    end

    def directive_files_on_disk
      return [] unless Dir.exist?(directives_dir)

      Dir.glob(File.join(directives_dir, "*.{md.erb,erb}"))
    end

    def directive_basename(path)
      File.basename(path).sub(/\.md\.erb$/, "").sub(/\.erb$/, "").to_sym
    end

    def directives_dir
      File.join(@project_root, "agents", @agent_name, "directives")
    end
  end
end
