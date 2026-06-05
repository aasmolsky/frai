# frozen_string_literal: true

require "fileutils"
require "json"

module Frai
  module Generators
    class TaskRemover
      def initialize(name)
        @name         = name
        @project_root = Dir.pwd
        @project_name = File.basename(@project_root)
        @task_dir     = File.join(@project_root, "tasks", name)
      end

      def remove
        abort "Error: task '#{@name}' not found." unless Dir.exist?(@task_dir)

        remove_task_files
        remove_skill
        remove_claude_md_entry
        remove_agents_md_entry
        remove_cursor_rules
        remove_mcp_if_no_tasks_left

        print_success
      end

      private

      def remove_task_files
        FileUtils.rm_rf(@task_dir)
        puts "  \e[31mremove\e[0m  tasks/#{@name}/"
      end

      # Skills are per-task — remove by task name
      def remove_skill
        claude_skill = File.expand_path("~/.claude/skills/#{@name}")
        if Dir.exist?(claude_skill)
          FileUtils.rm_rf(claude_skill)
          puts "  \e[31mremove\e[0m  ~/.claude/skills/#{@name}/"
        end

        codex_skill = File.expand_path("~/.codex/skills/#{@name}")
        if Dir.exist?(codex_skill)
          FileUtils.rm_rf(codex_skill)
          puts "  \e[31mremove\e[0m  ~/.codex/skills/#{@name}/"
        end
      end

      # CLAUDE.md entries are per-task — marker uses task name
      def remove_claude_md_entry
        path = File.expand_path("~/.claude/CLAUDE.md")
        return unless File.exist?(path)

        marker  = "<!-- frai:#{@name} -->"
        content = File.read(path)
        return unless content.include?(marker)

        # Split on all frai markers, drop the block belonging to @name
        parts   = content.split(/(<!-- frai:[^>]+ -->)/)
        result  = []
        skip    = false
        parts.each do |part|
          if part == marker
            skip = true
          elsif part =~ /<!-- frai:[^>]+ -->/
            skip = false
            result << part
          else
            result << part unless skip
          end
        end
        File.write(path, result.join.rstrip + "\n")
        puts "  \e[31mremove\e[0m  ~/.claude/CLAUDE.md entry"
      end

      # AGENTS.md entries are per-task
      def remove_agents_md_entry
        path = File.join(@project_root, "AGENTS.md")
        return unless File.exist?(path)

        marker  = "<!-- frai:#{@name} -->"
        content = File.read(path)
        return unless content.include?(marker)

        cleaned = content.gsub(/\n#{Regexp.escape(marker)}.+?(?=\n<!-- frai:|$)/m, "")
        File.write(path, cleaned)
        puts "  \e[31mremove\e[0m  AGENTS.md entry"
      end

      # Cursor rules are per-task
      def remove_cursor_rules
        path = File.join(@project_root, ".cursor", "rules", "#{@name}.mdc")
        return unless File.exist?(path)

        FileUtils.rm(path)
        puts "  \e[31mremove\e[0m  .cursor/rules/#{@name}.mdc"
      end

      # MCP server is per-project — only remove if no tasks remain
      def remove_mcp_if_no_tasks_left
        tasks_dir = File.join(@project_root, "tasks")
        remaining = Dir.glob(File.join(tasks_dir, "*/task.rb"))
        return unless remaining.empty?

        if system("which claude > /dev/null 2>&1")
          system("claude mcp remove #{@project_name} > /dev/null 2>&1")
          puts "  \e[31mremove\e[0m  MCP server (no tasks remaining)"
        end
        remove_cursor_mcp
        remove_approval_settings
      end

      def remove_cursor_mcp
        path = File.expand_path("~/.cursor/mcp.json")
        return unless File.exist?(path)

        config = JSON.parse(File.read(path))
        return unless config.dig("mcpServers", @project_name)

        config["mcpServers"].delete(@project_name)
        File.write(path, JSON.pretty_generate(config))
        puts "  \e[31mremove\e[0m  ~/.cursor/mcp.json entry"
      end

      def remove_approval_settings
        path = File.join(@project_root, ".claude", "settings.local.json")
        return unless File.exist?(path)

        settings = JSON.parse(File.read(path))
        pattern  = "mcp__#{@project_name}__*"
        allow    = settings.dig("permissions", "allow") || []
        return unless allow.include?(pattern)

        allow.delete(pattern)
        File.write(path, JSON.pretty_generate(settings))
        puts "  \e[31mremove\e[0m  .claude/settings.local.json entry"
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Task \e[1m#{@name}\e[0m removed"
        puts ""
      end
    end
  end
end
