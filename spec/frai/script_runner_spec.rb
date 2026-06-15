# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Frai::ScriptRunner do
  let(:root) { Dir.mktmpdir }
  let(:task_name) { "demo_task" }
  let(:scripts_dir) { File.join(root, "tasks", task_name, "scripts") }

  before { FileUtils.mkdir_p(scripts_dir) }

  after { FileUtils.rm_rf(root) }

  subject(:runner) { described_class.new(task_name, root) }

  def write_script(name, ext, body)
    File.write(File.join(scripts_dir, "#{name}.#{ext}"), body)
  end

  describe "Ruby call(input)" do
    it "runs def call(input) in-process" do
      write_script("prep", "rb", <<~RUBY)
        def call(input)
          { prepared: { value: input[:value], doubled: input[:value] * 2 } }
        end
      RUBY

      result = runner.run(:prep, { value: 5 })

      expect(result).to eq(prepared: { value: 5, doubled: 10 })
    end

    it "runs an expression using input in-process" do
      write_script("check", "rb", <<~RUBY)
        {
          check: {
            number: input,
            greater_than_10: input > 10
          }
        }
      RUBY

      result = runner.run(:check, 24)

      expect(result).to eq(check: { number: 24, greater_than_10: true })
    end

    it "memoizes repeated calls" do
      write_script("once", "rb", "def call(input); { n: input }; end")

      first  = runner.run(:once, 1)
      second = runner.run(:once, 99)

      expect(first).to eq(n: 1)
      expect(second).to eq(n: 1)
    end
  end

  describe "legacy Ruby JSON protocol" do
    it "still runs scripts that read stdin" do
      write_script("legacy", "rb", <<~RUBY)
        require "json"
        input = JSON.parse($stdin.read, symbolize_names: true)[:input]
        puts JSON.generate(result: { echo: input })
      RUBY

      result = runner.run(:legacy, "hello")

      expect(result).to eq(result: { echo: "hello" })
    end
  end

  describe "Python call(input) via shim", if: system("which python3 > /dev/null 2>&1") do
    it "runs def call(input) through the shim" do
      write_script("prep", "py", <<~PYTHON)
        def call(input):
            return {"prepared": {"value": input["value"], "doubled": input["value"] * 2}}
      PYTHON

      result = runner.run(:prep, { "value" => 5 })

      expect(result).to eq(prepared: { value: 5, doubled: 10 })
    end
  end

  describe "JavaScript call(input) via shim", if: system("which node > /dev/null 2>&1") do
    it "runs exported call through the shim" do
      write_script("prep", "js", <<~JS)
        function call(input) {
          return { prepared: { value: input.value, doubled: input.value * 2 } };
        }

        module.exports = { call };
      JS

      result = runner.run(:prep, { value: 5 })

      expect(result).to eq(prepared: { value: 5, doubled: 10 })
    end
  end

  describe "PHP call(input) via shim", if: system("which php > /dev/null 2>&1") do
    it "runs call(\$input) through the shim" do
      write_script("prep", "php", <<~PHP)
        <?php

        function call($input) {
            return ['prepared' => ['value' => $input['value'], 'doubled' => $input['value'] * 2]];
        }
      PHP

      result = runner.run(:prep, { "value" => 5 })

      expect(result).to eq(prepared: { value: 5, doubled: 10 })
    end
  end

  describe "TypeScript call(input) via shim", if: system("which tsx > /dev/null 2>&1") || system("which bun > /dev/null 2>&1") do
    it "runs exported call through the shim" do
      write_script("prep", "ts", <<~TS)
        export function call(input: { value: number }) {
          return { prepared: { value: input.value, doubled: input.value * 2 } };
        }
      TS

      result = runner.run(:prep, { value: 5 })

      expect(result).to eq(prepared: { value: 5, doubled: 10 })
    end
  end

  describe "errors" do
    it "raises when script is missing" do
      expect { runner.run(:missing, 1) }
        .to raise_error(Frai::MissingScript, /Script 'missing' not found/)
    end

    it "raises when Ruby script does not return a Hash" do
      write_script("bad", "rb", "42")

      expect { runner.run(:bad, 1) }
        .to raise_error(Frai::Error, /must return a Hash/)
    end
  end
end
