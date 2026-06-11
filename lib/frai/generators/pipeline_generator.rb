# frozen_string_literal: true

require "fileutils"
require_relative "base_generator"

module Frai
  module Generators
    class PipelineGenerator < BaseGenerator
      TEMPLATES_DIR = File.expand_path("templates/pipeline", __dir__)

      def initialize(name)
        @name       = name.delete_suffix("_pipeline")
        @class_name = @name.split("_").map(&:capitalize).join + "Pipeline"
        @target_dir = File.join(Dir.pwd, "pipelines")
      end

      def generate
        check_existing!
        copy_templates
        print_success
      end

      private

      def check_existing!
        file = File.join(@target_dir, "#{@name}_pipeline.rb")
        abort "Error: pipeline '#{@name}' already exists." if File.exist?(file)
      end

      def copy_templates
        src  = File.join(TEMPLATES_DIR, "pipeline.rb.erb")
        dest = File.join(@target_dir, "#{@name}_pipeline.rb")
        render_template(src, dest)
        say_create "pipelines/#{@name}_pipeline.rb"
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
