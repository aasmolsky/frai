# frozen_string_literal: true

require "erb"
require "fileutils"

module Frai
  module Setup
    # Slash command sync for `frai setup --claude`.
    # Resolves task class names from loaded classes (supports LLM-style acronyms).
    module Commands
      module_function

      # @param task_folder_name [String] e.g. "prepare_llm_report"
      # @param task_classes [Array<Class>] loaded Frai::Task subclasses
      # @return [String] e.g. "PrepareLLMReport::Task"
      def qualified_class_name(task_folder_name, task_classes)
        match = task_classes.find { |k| k.task_name == task_folder_name.to_s }
        return match.name if match

        fallback_class_name(task_folder_name)
      end

      # @param task_folder_name [String]
      # @return [String]
      def fallback_class_name(task_folder_name)
        "#{task_folder_name.to_s.split('_').map(&:capitalize).join}::Task"
      end

      # @param template_path [String]
      # @param name [String] slash command name (task folder)
      # @param qualified_class_name [String]
      # @return [String]
      def render_command(template_path, name:, qualified_class_name:)
        template = File.read(template_path)
        ERB.new(template, trim_mode: "-").result(binding)
      end

      # Creates, updates, and prunes .claude/commands/*.md for tasks.
      #
      # @return [Hash] :created, :updated, :present, :removed counts
      def sync!(root:, task_classes:, template_path:, output: $stdout)
        tasks_dir    = File.join(root, "tasks")
        commands_dir = File.join(root, ".claude", "commands")
        task_files   = Dir.glob(File.join(tasks_dir, "*/task.rb"))
        task_names   = task_files.map { |f| File.basename(File.dirname(f)) }

        counts = { created: 0, updated: 0, present: 0, removed: 0 }

        if task_files.empty?
          output.puts "  \e[33mskip\e[0m    No tasks found — skipping slash commands"
          return counts
        end

        state          = Frai::Setup::Mcp.load_state(root)
        managed_before = state["claude_commands"] || []

        (managed_before - task_names).each do |name|
          path = File.join(commands_dir, "#{name}.md")
          next unless File.exist?(path)

          FileUtils.rm(path)
          output.puts "  \e[31mremove\e[0m  .claude/commands/#{name}.md (orphan)"
          counts[:removed] += 1
        end

        task_files.each do |task_file|
          name                 = File.basename(File.dirname(task_file))
          class_name           = qualified_class_name(name, task_classes)
          command_file         = File.join(commands_dir, "#{name}.md")
          content              = render_command(template_path, name: name, qualified_class_name: class_name)

          FileUtils.mkdir_p(commands_dir)

          if File.exist?(command_file)
            if File.read(command_file) == content
              counts[:present] += 1
            else
              File.write(command_file, content)
              output.puts "  \e[32mupdate\e[0m  .claude/commands/#{name}.md"
              counts[:updated] += 1
            end
          else
            File.write(command_file, content)
            output.puts "  \e[32mcreate\e[0m  .claude/commands/#{name}.md"
            counts[:created] += 1
          end
        end

        state["claude_commands"] = task_names
        Frai::Setup::Mcp.save_state(root, state)

        output.puts "  \e[32m✓\e[0m Slash commands: #{counts[:created]} created, " \
                    "#{counts[:updated]} updated, #{counts[:present]} unchanged, " \
                    "#{counts[:removed]} orphan(s) removed"

        counts
      end
    end
  end
end
