# frozen_string_literal: true

require "fileutils"
require "erb"
require "json"

module Frai
  module Generators
    class SkillGenerator
      TEMPLATES_DIR = File.expand_path("../templates/skill", __FILE__)

      def initialize(project_name)
        @project_name = project_name
        @project_root = Dir.pwd
        @clients      = detect_clients
      end

      def generate
        if @clients.empty?
          abort "No supported AI clients found (Claude CLI, Codex CLI, or Cursor). Install one first."
        end

        puts "  \e[34mdetected\e[0m #{@clients.join(", ")}"
        puts ""

        @clients.each do |client|
          send(:"generate_#{client}")
        end

        print_success
      end

      private

      # --- client detection ---

      def detect_clients
        clients = []
        clients << :claude  if claude_installed?
        clients << :cursor  if cursor_installed?
        clients << :codex   if codex_installed?
        clients
      end

      def claude_installed?
        system("which claude > /dev/null 2>&1")
      end

      def cursor_installed?
        File.exist?(File.expand_path("~/.cursor")) ||
          File.exist?("/Applications/Cursor.app") ||
          system("which cursor > /dev/null 2>&1")
      end

      def codex_installed?
        File.exist?(File.expand_path("~/.codex")) ||
          system("which codex > /dev/null 2>&1")
      end

      # --- Claude CLI ---

      def generate_claude
        puts "  \e[34m[Claude CLI]\e[0m"
        generate_claude_skill
        update_claude_md
        register_claude_mcp
        puts ""
      end

      def generate_claude_skill
        target_dir = File.expand_path("~/.claude/skills/#{@project_name}")
        FileUtils.mkdir_p(target_dir)
        render_template("SKILL.md.erb", File.join(target_dir, "SKILL.md"))
      end

      def update_claude_md
        claude_md = File.expand_path("~/.claude/CLAUDE.md")
        FileUtils.mkdir_p(File.dirname(claude_md))
        existing = File.exist?(claude_md) ? File.read(claude_md) : ""
        marker   = "<!-- frai:#{@project_name} -->"
        return if existing.include?(marker)

        entry = <<~MD

          #{marker}
          ## #{@project_name}

          - The `#{@project_name}` MCP tools are **only** available through the `/#{@project_name}` skill
          - Never call `#{@project_name}` MCP tools directly — only when `/#{@project_name}` skill is explicitly invoked
          - Project root: `#{@project_root}`
        MD

        File.write(claude_md, existing + entry)
        puts "  \e[32mupdate\e[0m  ~/.claude/CLAUDE.md"
      end

      def register_claude_mcp
        cmd = "claude mcp add #{@project_name} -- frai serve --dir #{@project_root}"
        puts "  \e[33mrunning\e[0m claude mcp add #{@project_name} -- frai serve --dir #{@project_root}"
        if system(cmd)
          puts "  \e[32mupdate\e[0m  MCP server registered"
        else
          puts "  \e[31mwarn\e[0m    Run manually: #{cmd}"
        end
      end

      # --- Codex CLI ---

      def generate_codex
        puts "  \e[34m[Codex CLI]\e[0m"
        generate_codex_skill
        update_codex_mcp
        update_agents_md
        puts ""
      end

      def generate_codex_skill
        target_dir = File.expand_path("~/.codex/skills/#{@project_name}")
        FileUtils.mkdir_p(target_dir)
        render_template("SKILL.md.erb", File.join(target_dir, "SKILL.md"))
      end

      def update_codex_mcp
        cmd = "codex mcp add #{@project_name} -- frai serve --dir #{@project_root}"
        puts "  \e[33mrunning\e[0m codex mcp add #{@project_name} -- frai serve --dir #{@project_root}"
        if system(cmd)
          puts "  \e[32mupdate\e[0m  MCP server registered"
        else
          update_codex_toml
        end
      end

      def update_codex_toml
        toml_file = File.expand_path("~/.codex/config.toml")
        FileUtils.mkdir_p(File.dirname(toml_file))
        existing = File.exist?(toml_file) ? File.read(toml_file) : ""
        marker   = "# frai:#{@project_name}"
        return if existing.include?(marker)

        entry = <<~TOML

          #{marker}
          [mcp_servers.#{@project_name}]
          command = "frai"
          args    = ["serve", "--dir", "#{@project_root}"]
        TOML

        File.write(toml_file, existing + entry)
        puts "  \e[32mupdate\e[0m  ~/.codex/config.toml"
      end

      def update_agents_md
        agents_md = File.join(@project_root, "AGENTS.md")
        existing  = File.exist?(agents_md) ? File.read(agents_md) : ""
        marker    = "<!-- frai:#{@project_name} -->"
        return if existing.include?(marker)

        rendered = render_to_string("agents_md.erb")
        File.write(agents_md, existing + "\n" + rendered)
        puts "  \e[32mupdate\e[0m  AGENTS.md"
      end

      # --- Cursor ---

      def generate_cursor
        puts "  \e[34m[Cursor]\e[0m"
        update_cursor_mcp
        generate_cursor_rules
        puts ""
      end

      def update_cursor_mcp
        mcp_file = File.expand_path("~/.cursor/mcp.json")
        FileUtils.mkdir_p(File.dirname(mcp_file))
        config = File.exist?(mcp_file) ? JSON.parse(File.read(mcp_file)) : {}
        config["mcpServers"] ||= {}
        config["mcpServers"][@project_name] = {
          "command" => "frai",
          "args"    => ["serve", "--dir", @project_root]
        }
        File.write(mcp_file, JSON.pretty_generate(config))
        puts "  \e[32mupdate\e[0m  ~/.cursor/mcp.json"
      end

      def generate_cursor_rules
        rules_dir = File.join(@project_root, ".cursor", "rules")
        FileUtils.mkdir_p(rules_dir)
        render_template("cursor_rules.mdc.erb", File.join(rules_dir, "#{@project_name}.mdc"))
      end

      # --- shared ---

      def render_template(template, dest)
        result = render_to_string(template)
        File.write(dest, result)
        puts "  \e[32mcreate\e[0m  #{dest}"
      end

      def render_to_string(template)
        src = File.join(TEMPLATES_DIR, template)
        ERB.new(File.read(src), trim_mode: "-").result(binding)
      end

      def print_success
        puts "  \e[32m✓\e[0m Ready!"
        puts ""
        puts "  Claude CLI:  /#{@project_name}" if @clients.include?(:claude)
        puts "  Codex CLI:   /#{@project_name}" if @clients.include?(:codex)
        puts "  Cursor:      ask using @#{@project_name} context" if @clients.include?(:cursor)
        puts ""
      end
    end
  end
end
