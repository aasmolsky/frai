require "fileutils"
require "erb"

module Frai
  module Generators
    class AgentGenerator
      TEMPLATES_DIR = File.expand_path("../templates/agent", __FILE__)

      def initialize(name)
        @name       = name
        @class_name = name.split("_").map(&:capitalize).join + "Agent"
        @target_dir = File.join(Dir.pwd, "agents")
      end

      def generate
        copy_templates
        print_success
      end

      private

      def copy_templates
        src  = File.join(TEMPLATES_DIR, "agent.rb.erb")
        dest = File.join(@target_dir, "#{@name}_agent.rb")
        render_template(src, dest)
        say_create "agents/#{@name}_agent.rb"
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
        puts "  \e[32m✓\e[0m Generated agent \e[1m#{@class_name}\e[0m"
        puts ""
        puts "  Run it:"
        puts "    frai exec #{@class_name}"
        puts ""
      end
    end
  end
end
