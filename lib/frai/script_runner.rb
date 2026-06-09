# frozen_string_literal: true

require "json"
require "open3"

module Frai
  # Runs external scripts via stdin/stdout JSON protocol.
  #
  # Protocol:
  #   - Input:  { input: <value> } as JSON on stdin
  #   - Output: JSON hash on stdout
  #   - Exit 0 on success, non-zero on failure
  class ScriptRunner
    def initialize(task_name, project_root)
      @task_name    = task_name.to_s
      @project_root = project_root
      @cache        = {}
    end

    # All script results collected so far, keyed by script name.
    # @return [Hash{Symbol => Hash}]
    def results
      @cache
    end

    # Runs a script by name with the given input value.
    # Memoized per runner instance — same script called twice returns cached result.
    #
    # @param name [Symbol] script name
    # @param input [Object] input value — passed to script as { input: value }
    # @return [Hash] parsed JSON output from the script
    def run(name, input)
      return @cache[name] if @cache.key?(name)

      path = find_script!(name)

      stdout, stderr, status = Open3.capture3(
        interpreter_for(path), path,
        stdin_data: JSON.generate({ input: input })
      )

      unless status.success?
        raise Frai::Error,
          "Script '#{name}' failed (exit #{status.exitstatus}):\n#{stderr}"
      end

      @cache[name] = JSON.parse(stdout, symbolize_names: true)
    rescue JSON::ParserError => e
      raise Frai::Error, "Script '#{name}' returned invalid JSON: #{e.message}\nOutput was: #{stdout.to_s[0..200]}"
    end

    private

    def find_script!(name)
      local  = Dir.glob(File.join(@project_root, "tasks", @task_name, "scripts", "#{name}.*")).first
      global = Dir.glob(File.join(@project_root, "scripts", "#{name}.*")).first
      path   = local || global
      raise Frai::MissingScript, "Script '#{name}' not found." unless path

      path
    end

    def interpreter_for(path)
      case File.extname(path)
      when ".rb" then "ruby"
      when ".py" then "python3"
      when ".js" then "node"
      when ".sh" then "bash"
      else raise Frai::Error, "Unsupported script extension: #{File.extname(path)}"
      end
    end
  end
end
