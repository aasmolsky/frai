# frozen_string_literal: true

require "erb"
require "fileutils"

module Frai
  module Generators
    # Shared behaviour for all Frai generators.
    # Provides ERB rendering and coloured console output.
    class BaseGenerator
      private

      # Renders an ERB template into dest, using the subclass instance binding
      # so that all instance variables (@name, @class_name, etc.) are available.
      def render_template(src, dest)
        raw    = File.read(src)
        result = ERB.new(raw, trim_mode: "-").result(binding)
        File.write(dest, result)
      end

      # Prints a green "create" line to stdout.
      def say_create(path)
        puts "  \e[32mcreate\e[0m  #{path}"
      end
    end
  end
end
