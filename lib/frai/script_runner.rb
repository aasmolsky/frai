# frozen_string_literal: true

require "json"
require "open3"

require_relative "ruby_script"

module Frai
  # Runs task scripts and returns parsed JSON-compatible hashes.
  #
  # Default protocol — implement call(input):
  #   - .rb  in-process (expression or def call(input))
  #   - .py  python3 <shim> script.py
  #   - .js  node <shim> script.js
  #   - .php php <shim> script.php
  #   - .ts  tsx|bun|npx tsx <shim> script.ts
  #   - .sh  legacy subprocess (JSON stdin/stdout in the script)
  #
  # Legacy protocol (stdin/stdout JSON inside the script) is still supported
  # when the file contains $stdin, STDIN.read, JSON.parse, etc.
  class ScriptRunner
    SHIMS_DIR = File.expand_path("script_shims", __dir__)

    LEGACY_PROTOCOL_PATTERN = /
      \$stdin\b |
      \bSTDIN\.(?:read|gets)\b |
      \bJSON\.parse\b |
      \bjson\.load\s*\(\s*sys\.stdin |
      \breadFileSync\s*\(\s*0\b |
      require\s*\(\s*['"]fs['"]\s*\) |
      php:\/\/stdin |
      \bfile_get_contents\s*\(\s*['"]php:\/\/stdin['"]\s*\) |
      \bstream_get_contents\s*\(\s*STDIN\s*\)
    /x

    def initialize(task_name, project_root)
      @task_name     = task_name.to_s
      @project_root  = project_root
      @cache         = {}
      @return_values = {}
    end

    # All script results collected so far, keyed by script name.
    # @return [Hash{Symbol => Hash}]
    def results
      @cache
    end

    # All extracted return values, keyed by the return key declared in the directive.
    # @return [Hash{Symbol => Object}]
    def return_values
      @return_values
    end

    # Called by ScriptCall#and_return to register extracted values.
    def store_return(key, value)
      @return_values[key.to_sym] = value
    end

    # Runs a script by name with the given input value.
    # Memoized per runner instance — same script called twice returns cached result.
    #
    # @param name [Symbol] script name
    # @param input [Object] input value
    # @return [Hash] script output with symbol keys
    def run(name, input)
      return @cache[name] if @cache.key?(name)

      path = find_script!(name)
      @cache[name] = normalize_result!(name, execute(path, input))
    end

    private

    def execute(path, input)
      case File.extname(path)
      when ".rb"  then run_ruby(path, input)
      when ".py"  then run_python(path, input)
      when ".js"  then run_javascript(path, input)
      when ".php" then run_php(path, input)
      when ".ts"  then run_typescript(path, input)
      when ".sh"  then run_subprocess(path, input)
      else
        raise Frai::Error,
          "Unsupported script extension: #{File.extname(path)}. " \
          "Supported: .rb, .py, .js, .php, .ts, .sh"
      end
    end

    def run_ruby(path, input)
      if legacy_protocol?(path)
        run_subprocess(path, input)
      else
        RubyScript.run(path, input)
      end
    end

    def run_python(path, input)
      if legacy_protocol?(path)
        run_subprocess(path, input)
      else
        run_shim(%w[python3], shim_path("run.py"), path, input)
      end
    end

    def run_javascript(path, input)
      if legacy_protocol?(path)
        run_subprocess(path, input)
      else
        run_shim(%w[node], shim_path("run.js"), path, input)
      end
    end

    def run_php(path, input)
      if legacy_protocol?(path)
        run_subprocess(path, input)
      else
        run_shim(%w[php], shim_path("run.php"), path, input)
      end
    end

    def run_typescript(path, input)
      if legacy_protocol?(path)
        run_subprocess(path, input)
      else
        run_shim(typescript_runner_argv, shim_path("run.ts"), path, input)
      end
    end

    def run_shim(argv, shim, script_path, input)
      stdout, stderr, status = Open3.capture3(
        *argv, shim, script_path,
        stdin_data: JSON.generate({ input: input })
      )
      handle_subprocess_result(script_path, stdout, stderr, status)
    end

    def run_subprocess(path, input)
      stdout, stderr, status = Open3.capture3(
        *interpreter_argv_for(path), path,
        stdin_data: JSON.generate({ input: input })
      )
      handle_subprocess_result(path, stdout, stderr, status)
    end

    def handle_subprocess_result(path, stdout, stderr, status)
      name = File.basename(path, File.extname(path))

      unless status.success?
        raise Frai::Error,
          "Script '#{name}' failed (exit #{status.exitstatus}):\n#{stderr}"
      end

      JSON.parse(stdout, symbolize_names: true)
    rescue JSON::ParserError => e
      raise Frai::Error,
        "Script '#{name}' returned invalid JSON: #{e.message}\nOutput was: #{stdout[0, 200]}"
    end

    def normalize_result!(name, result)
      unless result.is_a?(Hash)
        raise Frai::Error, "Script '#{name}' must return a Hash, got #{result.class}"
      end

      result.transform_keys(&:to_sym)
    end

    def legacy_protocol?(path)
      return true if File.extname(path) == ".sh"

      File.read(path).match?(LEGACY_PROTOCOL_PATTERN)
    end

    def find_script!(name)
      local  = Dir.glob(File.join(@project_root, "tasks", @task_name, "scripts", "#{name}.*")).first
      global = Dir.glob(File.join(@project_root, "scripts", "#{name}.*")).first
      path   = local || global
      raise Frai::MissingScript, "Script '#{name}' not found." unless path

      path
    end

    def interpreter_argv_for(path)
      case File.extname(path)
      when ".rb"  then %w[ruby]
      when ".py"  then %w[python3]
      when ".js"  then %w[node]
      when ".php" then %w[php]
      when ".ts"  then typescript_runner_argv
      when ".sh"  then %w[bash]
      else
        raise Frai::Error,
          "Unsupported script extension: #{File.extname(path)}. " \
          "Supported: .rb, .py, .js, .php, .ts, .sh"
      end
    end

    def typescript_runner_argv
      return %w[tsx] if executable?("tsx")
      return %w[bun] if executable?("bun")

      %w[npx tsx]
    end

    def executable?(cmd)
      system("which", cmd, out: File::NULL, err: File::NULL)
    end

    def shim_path(filename)
      File.join(SHIMS_DIR, filename)
    end
  end
end
