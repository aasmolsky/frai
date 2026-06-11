# frozen_string_literal: true

require "fileutils"
require_relative "base_generator"

module Frai
  module Generators
    class NewGenerator < BaseGenerator
      TEMPLATES_DIR = File.expand_path("templates", __dir__)

      def initialize(project_name)
        @project_name = project_name
        @target_dir   = File.join(Dir.pwd, project_name)
      end

      def generate
        check_target_dir
        create_directories
        copy_templates
        print_success
      end

      private

      def check_target_dir
        abort "Error: directory '#{@project_name}' already exists." if Dir.exist?(@target_dir)
      end

      def create_directories
        dirs = %w[
          tasks
          pipelines
          agents
          applications
          mcp
          config
          spec
        ]
        dirs.each do |dir|
          path = File.join(@target_dir, dir)
          FileUtils.mkdir_p(path)
          say_create dir
        end
      end

      def copy_templates
        templates = {
          ".rspec.erb"                   => ".rspec",
          "tasks/base_task.rb.erb"       => "tasks/base_task.rb",
          "pipelines/base_pipeline.rb.erb"=> "pipelines/base_pipeline.rb",
          "agents/base_agent.rb.erb"      => "agents/base_agent.rb",
          "config/frai.rb.erb"            => "config/frai.rb",
          "spec/spec_helper.rb.erb"       => "spec/spec_helper.rb",
          "spec/conventions_spec.rb.erb"  => "spec/conventions_spec.rb",
          "README.md.erb"                 => "README.md",
          ".env.erb"                      => ".env",
          ".env.example.erb"              => ".env.example",
          ".gitignore.erb"                => ".gitignore",
        }

        templates.each do |template, target|
          src  = File.join(TEMPLATES_DIR, template)
          dest = File.join(@target_dir, target)
          render_template(src, dest)
          say_create target
        end
      end

      def render_template(src, dest)
        raw    = File.read(src)
        result = ERB.new(raw, trim_mode: "-").result(binding)
        File.write(dest, result)
      end

      # Override: prefix every path with the project name for clarity.
      def say_create(path)
        puts "  \e[32mcreate\e[0m  #{@project_name}/#{path}"
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Created project \e[1m#{@project_name}\e[0m"
        puts ""
        puts "  Next steps:"
        puts "    cd #{@project_name}"
        puts "    cp .env.example .env     # fill in your API keys"
        puts "    frai setup --claude      # optional: Claude CLI (MCPs + slash commands)"
        puts "    frai setup --codex       # optional: Codex CLI (MCP registration)"
        puts "    frai setup --cursor      # optional: Cursor (.cursor/mcp.json)"
        puts "    frai gt my_first_task    # generate your first task"
        puts ""
      end
    end
  end
end
