require "thor"
require "fileutils"
require "json"
require "erb"
require_relative "generators/new_generator"
require_relative "generators/task_generator"
require_relative "generators/task_remover"
require_relative "generators/project_destroyer"
require_relative "generators/pipeline_generator"
require_relative "generators/agent_generator"

module Frai
  # Command-line interface for the Frai framework.
  class CLI < Thor
    desc "new PROJECT_NAME", "Create a new Frai project"
    def new(project_name)
      Frai::Generators::NewGenerator.new(project_name).generate
    end

    desc "generate TYPE NAME", "Generate a task, pipeline, or agent"
    long_desc <<~DESC
      Types:
        task     — a single LLM call with its own directives and scripts
        pipeline — a sequential chain of tasks
        agent    — an orchestrator that decides which tasks and tools to call

      Examples:
        frai generate task fetch_data
        frai generate pipeline compare_objects
        frai generate agent object_comparison
    DESC
    def generate(type, name)
      generator = case type
                  when "task"     then Frai::Generators::TaskGenerator
                  when "pipeline" then Frai::Generators::PipelineGenerator
                  when "agent"    then Frai::Generators::AgentGenerator
                  else abort "Error: unknown type '#{type}'. Use: task, pipeline, agent"
                  end
      generator.new(name).generate
    end

    desc "destroy", "Remove all MCP servers and Claude CLI commands for this project"
    long_desc <<~DESC
      Cleans up all external artifacts before deleting the project directory.
      Run from inside the project, then delete the directory manually.

      Example:
        frai destroy
        rm -rf ../my_project
    DESC
    def destroy
      load_project!
      Frai::Generators::ProjectDestroyer.new.destroy
    end

    desc "remove task TASK_NAME", "Remove a task and its Claude CLI command"
    def remove(type, task_name)
      abort "Error: unknown type '#{type}'. Use: task" unless type == "task"
      load_project!
      Frai::Generators::TaskRemover.new(task_name).remove
    end

    desc "exec CLASS_NAME [INPUT]", "Execute a task, pipeline or agent"
    long_desc <<~DESC
      Runs a task from the current project. INPUT can be:
        - a plain string: frai exec AnalyzeItemTask "some text"
        - key:value pairs: frai exec CodeReviewTask task_number:PDB-111
        - name(value) format: frai exec CodeReviewTask "task_number(PDB-111)"

      Examples:
        frai exec AnalyzeItemTask "some input"
        frai exec CodeReviewTask task_number:PDB-111
        frai exec SumNumbersTask "input_numbers(1,2,3)"
    DESC
    def exec(class_name, input = nil)
      load_project!
      Frai.configuration.adapter ||= :null
      parsed = parse_input(input)
      result = Object.const_get(class_name).call(parsed)
      puts result
    rescue Frai::MissingParam, Frai::InvalidParam => e
      klass  = Object.const_get(class_name) rescue nil
      params = klass&._directive_declaration&.params_declaration
      required = params&.required_params&.keys&.map { |k| "#{k}(value)" }&.join(" ")
      abort "Error: #{e.message}\n\nUsage: frai exec #{class_name} \"#{required}\""
    rescue Frai::Error => e
      abort "Error: #{e.message}"
    rescue NameError
      abort "Error: task class '#{class_name}' not found. Check the class name."
    rescue => e
      abort "Error: #{e.message}"
    end

    desc "setup", "Register all project MCP servers with Claude CLI and Codex"
    long_desc <<~DESC
      Reads mcp/*.rb files and registers each defined server with Claude CLI.
      Run once after cloning the project or adding new MCP definitions.

      Example:
        frai setup
    DESC
    def setup
      load_project!
      load_mcps!

      servers = Frai::MCP.all
      abort "No MCP servers defined in mcp/. Add definitions and try again." if servers.empty?

      servers.each do |server|
        register_mcp(server)
      end

      allow_mcp_permissions(servers)
      sync_commands

      puts ""
      puts "  \e[32m✓\e[0m Setup complete. Restart Claude CLI to apply."
    end

    desc "console", "Start an interactive console with the project loaded"
    def console
      load_project!
      require "irb"
      ARGV.clear
      IRB.start(__FILE__)
    end

    map "g"  => "generate"
    map "r"  => "remove"
    map "c"  => "console"
    map "e"  => "exec"
    map "n"  => "new"
    map "s"  => "setup"

    desc "gt NAME", "Shortcut for: generate task NAME"
    def gt(name) = generate("task", name)

    desc "gp NAME", "Shortcut for: generate pipeline NAME"
    def gp(name) = generate("pipeline", name)

    desc "ga NAME", "Shortcut for: generate agent NAME"
    def ga(name) = generate("agent", name)

    desc "rt NAME", "Shortcut for: remove task NAME"
    def rt(name) = remove("task", name)

    def self.exit_on_failure?
      true
    end

    private

    def load_project!
      config = File.join(Dir.pwd, "config", "frai.rb")
      abort "Error: config/frai.rb not found. Are you inside a Frai project?" unless File.exist?(config)
      require config
    end

    def allow_mcp_permissions(servers)
      settings_file = File.join(Dir.pwd, ".claude", "settings.local.json")
      FileUtils.mkdir_p(File.dirname(settings_file))
      settings = File.exist?(settings_file) ? JSON.parse(File.read(settings_file)) : {}
      settings["permissions"] ||= {}
      settings["permissions"]["allow"] ||= []

      # Allow frai exec without approval prompts
      unless settings["permissions"]["allow"].include?("Bash(frai exec *)")
        settings["permissions"]["allow"] << "Bash(frai exec *)"
      end

      servers.each do |server|
        pattern = "mcp__#{server.name}__*"
        unless settings["permissions"]["allow"].include?(pattern)
          settings["permissions"]["allow"] << pattern
        end
      end

      File.write(settings_file, JSON.pretty_generate(settings))
      puts "  \e[32mupdate\e[0m  .claude/settings.local.json (MCP approvals disabled)"
    end

    def sync_commands
      tasks_dir    = File.join(Dir.pwd, "tasks")
      commands_dir = File.join(Dir.pwd, ".claude", "commands")
      templates    = File.expand_path("../generators/templates/commands", __FILE__)

      Dir.glob(File.join(tasks_dir, "*/task.rb")).each do |task_file|
        @name        = File.basename(File.dirname(task_file))
        @class_name  = @name.split("_").map(&:capitalize).join + "Task"
        command_file = File.join(commands_dir, "#{@name}.md")
        next if File.exist?(command_file)

        FileUtils.mkdir_p(commands_dir)
        src    = File.join(templates, "task.md.erb")
        result = ERB.new(File.read(src), trim_mode: "-").result(binding)
        File.write(command_file, result)
        puts "  \e[32mcreate\e[0m  .claude/commands/#{@name}.md"
      end
    end

    def load_mcps!
      Dir[File.join(Dir.pwd, "mcp", "*.rb")].each { |f| require f }
    end

    def register_mcp(server)
      cmd = if server.type == :http
        ["claude", "mcp", "add", "--scope", "local",
         "--transport", "http",
         server.name.to_s, server.url_value].join(" ")
      else
        env_args  = server.env_value.flat_map { |k, v| ["-e", "#{k}=#{v}"] }
        cmd_parts = [server.command_value] + server.args_value.map do |a|
          a.start_with?("~", "/") ? File.expand_path(a) : a
        end
        ["claude", "mcp", "add", "--scope", "local",
         server.name.to_s, *env_args, "--", *cmd_parts].join(" ")
      end

      puts "  \e[33mregistering\e[0m #{server.name} (#{server.type})"
      output = `#{cmd} 2>&1`
      if $?.success?
        puts "  \e[32m✓\e[0m #{server.name} registered"
      elsif output.include?("already exists")
        puts "  \e[32m✓\e[0m #{server.name} already registered"
      else
        puts "  \e[31mwarn\e[0m    Failed: #{output.strip}"
      end
    end

    # Parses input string into a Hash or returns as-is.
    #
    # Supports:
    #   "key(value) key2(value2)"  → { key: "value", key2: "value2" }
    #   "key:value key2:value2"    → { key: "value", key2: "value2" }
    #   "plain string"             → "plain string"
    #   nil                        → nil
    def parse_input(input)
      return nil if input.nil? || input.strip.empty?

      # name(value) format
      if input.match?(/\w+\([^)]*\)/)
        pairs = input.scan(/(\w+)\(([^)]*)\)/)
        return pairs.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      # key:value format
      if input.match?(/\w+:\S+/)
        pairs = input.scan(/(\w+):(\S+)/)
        return pairs.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      input
    end
  end
end
