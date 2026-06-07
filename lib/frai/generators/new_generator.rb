require "fileutils"
require "erb"

module Frai
  module Generators
    class NewGenerator
      TEMPLATES_DIR = File.expand_path("../templates", __FILE__)

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
        if Dir.exist?(@target_dir)
          abort "Error: directory '#{@project_name}' already exists."
        end
      end

      def create_directories
        dirs = %w[
          directives
          tasks
          pipelines
          agents
          scripts
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
          "directives/base.md.erb.erb"    => "directives/base.md.erb",
          "tasks/base_task.rb.erb"        => "tasks/base_task.rb",
          "pipelines/base_pipeline.rb.erb"=> "pipelines/base_pipeline.rb",
          "agents/base_agent.rb.erb"      => "agents/base_agent.rb",
          "config/frai.rb.erb"            => "config/frai.rb",
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

      def say_create(path)
        puts "  \e[32mcreate\e[0m  #{@project_name}/#{path}"
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Created project \e[1m#{@project_name}\e[0m"
        puts ""
        puts "  Next steps:"
        puts "    cd #{@project_name}"
        puts "    frai console"
        puts ""
      end
    end
  end
end
