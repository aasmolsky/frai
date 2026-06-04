require "fileutils"
require "erb"

module Frai
  module Generators
    class PipelineGenerator
      TEMPLATES_DIR = File.expand_path("../templates/pipeline", __FILE__)

      def initialize(name)
        @name       = name
        @class_name = name.split("_").map(&:capitalize).join + "Pipeline"
        @target_dir = File.join(Dir.pwd, "pipelines")
      end

      def generate
        copy_templates
        print_success
      end

      private

      def copy_templates
        src  = File.join(TEMPLATES_DIR, "pipeline.rb.erb")
        dest = File.join(@target_dir, "#{@name}_pipeline.rb")
        render_template(src, dest)
        say_create "pipelines/#{@name}_pipeline.rb"
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
        puts "  \e[32m✓\e[0m Generated pipeline \e[1m#{@class_name}\e[0m"
        puts ""
        puts "  Run it:"
        puts "    frai exec #{@class_name}"
        puts ""
      end
    end
  end
end
