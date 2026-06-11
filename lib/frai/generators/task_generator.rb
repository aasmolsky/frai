# frozen_string_literal: true

require "fileutils"
require_relative "base_generator"

module Frai
  module Generators
    class TaskGenerator < BaseGenerator
      TEMPLATES_DIR = File.expand_path("templates/task", __dir__)

      def initialize(name)
        @name                = name
        @module_name         = name.split("_").map(&:capitalize).join
        @qualified_class_name = "#{@module_name}::Task"
        @target_dir          = File.join(Dir.pwd, "tasks", name)
      end

      def generate
        check_target_dir
        create_directories
        copy_templates
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
          "task.rb.erb"                => "task.rb",
          "directives/task.md.erb.erb" => "directives/task.md.erb"
        }.each do |template, target|
          src  = File.join(TEMPLATES_DIR, template)
          dest = File.join(@target_dir, target)
          render_template(src, dest)
          say_create "tasks/#{@name}/#{target}"
        end
      end

      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Generated task \e[1m#{@qualified_class_name}\e[0m"
        puts ""
        puts "  Run:"
        puts "    frai exec #{@qualified_class_name} \"param_name(value)\""
        puts ""
        puts "  Client setup (optional):"
        puts "    frai setup --claude   # or --codex / --cursor"
        puts ""
      end
    end
  end
end
