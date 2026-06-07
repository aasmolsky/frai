require "fileutils"
require "erb"

module Frai
  module Generators
    class TaskGenerator
      TEMPLATES_DIR  = File.expand_path("../templates/task",     __FILE__)
      COMMANDS_DIR   = File.expand_path("../templates/commands", __FILE__)

      def initialize(name)
        @name       = name
        @class_name = name.split("_").map(&:capitalize).join + "Task"
        @target_dir = File.join(Dir.pwd, "tasks", name)
      end

      def generate
        check_target_dir
        create_directories
        copy_templates
        create_claude_command
        print_success
      end

      private

      def check_target_dir
        abort "Error: task '#{@name}' already exists." if Dir.exist?(@target_dir)
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
          "task.kdl.erb"               => "task.kdl",
          "task.rb.erb"                => "task.rb",
          "directives/main.md.erb.erb" => "directives/main.md.erb"
        }.each do |template, target|
          src  = File.join(TEMPLATES_DIR, template)
          dest = File.join(@target_dir, target)
          render_template(src, dest)
          say_create "tasks/#{@name}/#{target}"
        end
      end

      def create_claude_command
        commands_dir = File.join(Dir.pwd, ".claude", "commands")
        FileUtils.mkdir_p(commands_dir)
        src  = File.join(COMMANDS_DIR, "task.md.erb")
        dest = File.join(commands_dir, "#{@name}.md")
        render_template(src, dest)
        say_create ".claude/commands/#{@name}.md"
      end

      def render_template(src, dest)
        raw    = File.read(src)
        result = ERB.new(raw, trim_mode: "-").result(binding)
        File.write(dest, result)
      end

      def say_create(path)
        puts "  \e[32mcreate\e[0m  #{path}"
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Generated task \e[1m#{@class_name}\e[0m"
        puts ""
        puts "  Use in Claude CLI (from this project directory):"
        puts "    /#{@name} param_name(value)"
        puts ""
        puts "  Run directly:"
        puts "    frai exec #{@class_name} \"param_name(value)\""
        puts ""
      end
    end
  end
end
