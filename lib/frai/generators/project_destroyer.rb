# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../setup/mcp"

module Frai
  module Generators
    class ProjectDestroyer
      def initialize
        @project_root = Dir.pwd
        @project_name = File.basename(@project_root)
      end

      def destroy
        puts "  \e[31mDestroying project\e[0m \e[1m#{@project_name}\e[0m"
        puts ""

        server_names = mcp_server_names
        remove_mcps(server_names)
        remove_cursor_mcps(server_names)
        remove_commands

        puts ""
        puts "  \e[32m✓\e[0m Cleanup done. Now delete the project directory:"
        puts ""
        puts "    rm -rf #{@project_root}"
        puts ""
      end

      private

      def mcp_server_names
        names = Frai::MCP.all.map { |s| s.name.to_s }
        return names unless names.empty?

        # Legacy projects may only have .mcp.json
        mcp_json = File.join(@project_root, ".mcp.json")
        return [] unless File.exist?(mcp_json)

        Frai::Setup::Mcp.parse_json_file(mcp_json, label: ".mcp.json")
          .dig("mcpServers")&.keys || []
      end

      def remove_mcps(server_names)
        server_names.each do |name|
          if system("claude", "mcp", "remove", name, out: File::NULL, err: File::NULL)
            puts "  \e[31mremove\e[0m  Claude MCP: #{name}"
          end

          if system("codex", "mcp", "remove", name, out: File::NULL, err: File::NULL)
            puts "  \e[31mremove\e[0m  Codex MCP: #{name}"
          end
        end
      end

      def remove_cursor_mcps(server_names)
        return if server_names.empty?

        mcp_file = File.join(@project_root, ".cursor", "mcp.json")
        return unless File.exist?(mcp_file)

        config = Frai::Setup::Mcp.parse_json_file(mcp_file, label: ".cursor/mcp.json")
        servers = config["mcpServers"] || {}
        removed = 0

        server_names.each do |name|
          next unless servers.delete(name)

          puts "  \e[31mremove\e[0m  Cursor MCP: #{name}"
          removed += 1
        end

        return if removed.zero?

        if servers.empty?
          FileUtils.rm(mcp_file)
          puts "  \e[31mremove\e[0m  .cursor/mcp.json (empty)"
        else
          File.write(mcp_file, JSON.pretty_generate(config) + "\n")
          puts "  \e[32mupdate\e[0m  .cursor/mcp.json"
        end
      end

      def remove_commands
        commands_dir = File.join(@project_root, ".claude", "commands")
        return unless Dir.exist?(commands_dir)

        Dir.glob(File.join(commands_dir, "*.md")).each do |f|
          puts "  \e[31mremove\e[0m  .claude/commands/#{File.basename(f)}"
        end
        puts "  \e[33mnote\e[0m    Command files will be removed with the project directory"
      end
    end
  end
end
