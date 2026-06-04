require "json"
require "open3"

module Frai
  # Runs external scripts and memoizes their results.
  # Each script is executed at most once per task call.
  #
  # Script contract:
  #   - receives JSON on stdin (only the params declared with `with:`)
  #   - writes JSON to stdout
  #   - exits with code 0 on success, non-zero on failure
  #   - output is validated against `returns:` contract if declared
  class ScriptRunner
    def initialize(task_name, project_root)
      @task_name    = task_name.to_s
      @project_root = project_root
      @cache        = {}
    end

    # Runs a script and returns its parsed JSON result.
    # Memoized — subsequent calls with the same name return cached result.
    #
    # @param script_decl [DirectiveDeclaration::ScriptDeclaration]
    # @param available_params [Hash] all params available in the current directive
    # @return [Hash] parsed JSON output from the script
    def run(script_decl, available_params = {})
      @cache[script_decl.name] ||= execute(script_decl, available_params)
    end

    # Returns cached result for a script by name (without re-running).
    # Used in ERB context to access already-run script results.
    #
    # @param name [Symbol]
    # @return [Hash, nil]
    def result(name)
      @cache[name]
    end

    private

    def execute(script_decl, available_params)
      path = find_script(script_decl.name)
      raise Frai::MissingScript, "script :#{script_decl.name} not found" unless path

      # Build input: only pass params declared with `with:`
      input = build_input(script_decl.with, available_params)

      stdout, stderr, status = Open3.capture3(
        interpreter_for(path), path,
        stdin_data: JSON.generate(input)
      )

      unless status.success?
        raise Frai::Error,
          "script '#{script_decl.name}' failed (exit #{status.exitstatus}):\n#{stderr}"
      end

      result = JSON.parse(stdout, symbolize_names: true)

      # Validate output against returns: contract if declared
      validate_output!(script_decl, result) if script_decl.returns

      result
    rescue JSON::ParserError => e
      raise Frai::Error, "script '#{script_decl.name}' returned invalid JSON: #{e.message}"
    end

    # Builds input hash for the script based on `with:` declaration.
    # If with: is nil — passes all available params.
    # If with: is a Symbol — passes { name => value }.
    # If with: is an Array — passes only those keys.
    def build_input(with_param, available_params)
      return available_params if with_param.nil?

      keys = Array(with_param)
      available_params.select { |k, _| keys.include?(k) }
    end

    # Validates script output against the declared returns: contract.
    # returns: expects a Hash like { total: Integer }
    def validate_output!(script_decl, result)
      script_decl.returns.each do |key, type|
        unless result.key?(key)
          raise Frai::InvalidScriptOutput,
            "script '#{script_decl.name}' expected to return key :#{key} " \
            "but it was missing from output: #{result.inspect}"
        end

        unless result[key].is_a?(type)
          raise Frai::InvalidScriptOutput,
            "script '#{script_decl.name}' :#{key} expected #{type}, " \
            "got #{result[key].class}"
        end
      end
    end

    def find_script(name)
      local  = Dir.glob(File.join(@project_root, "tasks", @task_name, "scripts", "#{name}.*")).first
      global = Dir.glob(File.join(@project_root, "scripts", "#{name}.*")).first
      local || global
    end

    def interpreter_for(path)
      case File.extname(path)
      when ".py"   then "python3"
      when ".js"   then "node"
      when ".rb"   then "ruby"
      when ".sh"   then "bash"
      else ""
      end
    end
  end
end
