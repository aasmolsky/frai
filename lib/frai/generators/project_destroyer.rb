# frozen_string_literal: true

require "fileutils"
require "json"

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

        remove_mcps
        remove_commands

        puts ""
        puts "  \e[32m✓\e[0m Cleanup done. Now delete the project directory:"
        puts ""
        puts "    rm -rf #{@project_root}"
        puts ""
      end

      private

      def remove_mcps
        mcp_json = File.join(@project_root, ".mcp.json")
        return unless File.exist?(mcp_json)

        servers = JSON.parse(File.read(mcp_json)).dig("mcpServers") || {}
        servers.each_key do |name|
          system("claude mcp remove #{name} > /dev/null 2>&1")
          puts "  \e[31mremove\e[0m  MCP server: #{name}"
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
