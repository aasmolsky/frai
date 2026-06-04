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
        remove_mcp
        remove_skill
        remove_claude_md_entry
        remove_codex_entry
        remove_agents_md_entry
        remove_cursor_rules
        remove_approval_settings

        print_success
      end

      private

      def remove_task_files
        FileUtils.rm_rf(@task_dir)
        puts "  \e[31mremove\e[0m  tasks/#{@name}/"
      end

      def remove_mcp
        if system("which claude > /dev/null 2>&1")
          system("claude mcp remove #{@project_name} > /dev/null 2>&1")
          puts "  \e[31mremove\e[0m  MCP server (Claude CLI)"
        end
        if system("which codex > /dev/null 2>&1")
          system("codex mcp remove #{@project_name} > /dev/null 2>&1")
          remove_codex_toml_entry
          puts "  \e[31mremove\e[0m  MCP server (Codex CLI)"
        end
        remove_cursor_mcp
      end

      def remove_skill
        claude_skill = File.expand_path("~/.claude/skills/#{@project_name}")
        if Dir.exist?(claude_skill)
          FileUtils.rm_rf(claude_skill)
          puts "  \e[31mremove\e[0m  ~/.claude/skills/#{@project_name}/"
        end

        codex_skill = File.expand_path("~/.codex/skills/#{@project_name}")
        if Dir.exist?(codex_skill)
          FileUtils.rm_rf(codex_skill)
          puts "  \e[31mremove\e[0m  ~/.codex/skills/#{@project_name}/"
        end
      end

      def remove_claude_md_entry
        path = File.expand_path("~/.claude/CLAUDE.md")
        return unless File.exist?(path)

        marker = "<!-- frai:#{@project_name} -->"
        content = File.read(path)
        return unless content.include?(marker)

        # Remove block from marker to next marker or end of file
        cleaned = content.gsub(/\n#{Regexp.escape(marker)}.+?(?=\n<!-- frai:|$)/m, "")
        File.write(path, cleaned)
        puts "  \e[31mremove\e[0m  ~/.claude/CLAUDE.md entry"
      end

      def remove_codex_toml_entry
        path = File.expand_path("~/.codex/config.toml")
        return unless File.exist?(path)

        marker = "# frai:#{@project_name}"
        content = File.read(path)
        return unless content.include?(marker)

        cleaned = content.gsub(/\n#{Regexp.escape(marker)}.+?\n\[/m) { "\n[" }
        File.write(path, cleaned)
      end

      def remove_codex_entry
        # handled in remove_codex_toml_entry called from remove_mcp
      end

      def remove_agents_md_entry
        path = File.join(@project_root, "AGENTS.md")
        return unless File.exist?(path)

        marker = "<!-- frai:#{@project_name} -->"
        content = File.read(path)
        return unless content.include?(marker)

        cleaned = content.gsub(/\n#{Regexp.escape(marker)}.+?(?=\n<!-- frai:|$)/m, "")
        File.write(path, cleaned)
        puts "  \e[31mremove\e[0m  AGENTS.md entry"
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

      def remove_cursor_rules
        path = File.join(@project_root, ".cursor", "rules", "#{@project_name}.mdc")
        return unless File.exist?(path)

        FileUtils.rm(path)
        puts "  \e[31mremove\e[0m  .cursor/rules/#{@project_name}.mdc"
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
        puts "  \e[32m✓\e[0m Task \e[1m#{@name}\e[0m and its skill removed"
        puts ""
      end
    end
  end
end
