# frozen_string_literal: true

require "fileutils"
require_relative "base_generator"

module Frai
  module Generators
    class AgentGenerator < BaseGenerator
      TEMPLATES_DIR = File.expand_path("templates/agent", __dir__)

      def initialize(name)
        @name       = name.delete_suffix("_agent")
        @class_name = @name.split("_").map(&:capitalize).join + "Agent"
        @target_dir = File.join(Dir.pwd, "agents")
      end

      def generate
        check_existing!
        create_directories
        copy_templates
        print_success
      end

      private

      def check_existing!
        file = File.join(@target_dir, "#{@name}_agent.rb")
        abort "Error: agent '#{@name}' already exists." if File.exist?(file)
      end

      def create_directories
        directives_dir = File.join(@target_dir, @name, "directives")
        FileUtils.mkdir_p(directives_dir)
        say_create "agents/#{@name}/directives/"
      end

      def copy_templates
        {
          "agent.rb.erb"                        => "#{@name}_agent.rb",
          "directives/instructions.md.erb.erb"  => "#{@name}/directives/instructions.md.erb"
        }.each do |template, target|
          src  = File.join(TEMPLATES_DIR, template)
          dest = File.join(@target_dir, target)
          render_template(src, dest)
          say_create "agents/#{target}"
        end
      end


      def print_success
        puts ""
        puts "  \e[32m✓\e[0m Generated agent \e[1m#{@class_name}\e[0m"
        puts ""
        puts "  Run it:"
        puts "    frai exec #{@class_name}"
        puts ""
      end
    end
  end
end
