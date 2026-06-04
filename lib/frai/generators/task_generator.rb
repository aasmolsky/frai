require "fileutils"
require "erb"
require_relative "skill_generator"

module Frai
  module Generators
    class TaskGenerator
      TEMPLATES_DIR = File.expand_path("../templates/task", __FILE__)

      def initialize(name)
        @name       = name  # e.g. "get_toyota_data"
        @class_name = name.split("_").map(&:capitalize).join + "Task"
        @target_dir = File.join(Dir.pwd, "tasks", name)
      end

      def generate
        check_target_dir
        create_directories
        copy_templates
        update_skill
        print_success
      end

      private

      def check_target_dir
        if Dir.exist?(@target_dir)
          abort "Error: task '#{@name}' already exists."
        end
      end

      def create_directories
        FileUtils.mkdir_p(File.join(@target_dir, "directives"))
        FileUtils.mkdir_p(File.join(@target_dir, "scripts"))
        say_create "tasks/#{@name}/"
        say_create "tasks/#{@name}/directives/"
        say_create "tasks/#{@name}/scripts/"
      end

      def copy_templates
        {
          "task.rb.erb"                => "task.rb",
          "directives/main.md.erb.erb" => "directives/main.md.erb",
        }.each do |template, target|
          src  = File.join(TEMPLATES_DIR, template)
          dest = File.join(@target_dir, target)
          render_template(src, dest)
          say_create "tasks/#{@name}/#{target}"
        end
      end

      def render_template(src, dest)
        raw    = File.read(src)
        result = ERB.new(raw, trim_mode: "-").result(binding)
        File.write(dest, result)
      end

      def update_skill
        project_name = File.basename(Dir.pwd)
        puts ""
        puts "  \e[34mcreating skill\e[0m /#{@name}"
        SkillGenerator.new(@name, project_name).generate
      rescue => e
        puts "  \e[31mwarn\e[0m    Could not create skill: #{e.message}"
      end

      def say_create(path)
        puts "  \e[32mcreate\e[0m  #{path}"
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Generated task \e[1m#{@class_name}\e[0m"
        puts ""
        puts "  Edit your directive:"
        puts "    tasks/#{@name}/directives/main.md.erb"
        puts ""
        puts "  Run it:"
        puts "    frai exec #{@class_name}"
        puts ""
      end
    end
  end
end
