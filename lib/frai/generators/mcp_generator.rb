require "fileutils"
require "erb"

module Frai
  module Generators
    class McpGenerator
      TEMPLATES_DIR = File.expand_path("../templates/mcp", __FILE__)

      def initialize(name)
        @name       = name
        @target_dir = File.join(Dir.pwd, "mcp")
      end

      def generate
        copy_templates
        print_success
      end

      private

      def copy_templates
        src  = File.join(TEMPLATES_DIR, "server.rb.erb")
        dest = File.join(@target_dir, "#{@name}.rb")
        render_template(src, dest)
        say_create "mcp/#{@name}.rb"
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
        puts "  \e[32m✓\e[0m Generated MCP server \e[1m#{@name}\e[0m"
        puts ""
        puts "  Configure the server in:"
        puts "    mcp/#{@name}.rb"
        puts ""
        puts "  Then declare it in your task:"
        puts "    directive :main do"
        puts "      mcp :#{@name}"
        puts "    end"
        puts ""
      end
    end
  end
end
