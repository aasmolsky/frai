# frozen_string_literal: true

module Frai
  # Runs a Ruby script in-process with `input` in scope.
  # Supports `def call(input)` or a final expression using `input`.
  module RubyScript
    module_function

    def run(path, input)
      source = File.read(path)
      use_call_method = method_style?(source)
      ctx = Object.new
      ctx.instance_exec(input, source, path, use_call_method) do |inp, src, p, call_method|
        input = inp
        if call_method
          eval(src, binding, p) # rubocop:disable Security/Eval
          call(inp)
        else
          eval(src, binding, p) # rubocop:disable Security/Eval
        end
      end
    end

    def method_style?(source)
      source.match?(/\bdef\s+call\s*[\(\n]/)
    end
  end
end
