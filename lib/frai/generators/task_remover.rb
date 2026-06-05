# frozen_string_literal: true

require "fileutils"

module Frai
  module Generators
    class TaskRemover
      def initialize(name)
        @name         = name
        @project_root = Dir.pwd
        @task_dir     = File.join(@project_root, "tasks", name)
      end

      def remove
        abort "Error: task '#{@name}' not found." unless Dir.exist?(@task_dir)

        remove_task_files
        remove_claude_command

        print_success
      end

      private

      def remove_task_files
        FileUtils.rm_rf(@task_dir)
        puts "  \e[31mremove\e[0m  tasks/#{@name}/"
      end

      def remove_claude_command
        path = File.join(@project_root, ".claude", "commands", "#{@name}.md")
        return unless File.exist?(path)

        FileUtils.rm(path)
        puts "  \e[31mremove\e[0m  .claude/commands/#{@name}.md"
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Task \e[1m#{@name}\e[0m removed"
        puts ""
      end
    end
  end
end
