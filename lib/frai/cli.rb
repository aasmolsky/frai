require "thor"
require_relative "generators/new_generator"
require_relative "generators/task_generator"
require_relative "generators/pipeline_generator"
require_relative "generators/agent_generator"
require_relative "generators/mcp_generator"

module Frai
  # Command-line interface for the Frai framework.
  # Provides commands for creating projects, generating components, and running tasks.
  class CLI < Thor
    desc "new PROJECT_NAME", "Create a new Frai project"
    long_desc <<~DESC
      Creates a new Frai project with the standard directory structure.

      Example:
        frai new my_project
        cd my_project
        bundle install
    DESC
    def new(project_name)
      Frai::Generators::NewGenerator.new(project_name).generate
    end

    desc "generate TYPE NAME", "Generate a task, pipeline, agent or MCP server"
    long_desc <<~DESC
      Generates a new component with all related files.

      Types:
        task     — a single LLM call with its own directives and scripts
        pipeline — a sequential chain of tasks
        agent    — an orchestrator that decides which tasks and tools to call
        mcp      — an MCP server definition (for use in task directive blocks)

      Name should be in snake_case.

      Examples:
        frai generate task fetch_data
        frai generate task analyze_item
        frai generate pipeline compare_objects
        frai generate agent object_comparison
        frai generate mcp browser
        frai generate mcp filesystem
    DESC
    def generate(type, name)
      generator = case type
                  when "task"     then Frai::Generators::TaskGenerator
                  when "pipeline" then Frai::Generators::PipelineGenerator
                  when "agent"    then Frai::Generators::AgentGenerator
                  when "mcp"      then Frai::Generators::McpGenerator
                  else abort "Error: unknown type '#{type}'. Use: task, pipeline, agent, mcp"
                  end
      generator.new(name).generate
    end

    desc "console", "Start an interactive console with the project loaded"
    long_desc <<~DESC
      Starts an IRB session with the current Frai project fully loaded.
      Useful for quickly testing tasks without writing a script.
      Run from inside your project directory.

      Example:
        frai console
        irb> AnalyzeItemTask.call("some input")
    DESC
    def console
      load_project!
      require "irb"
      ARGV.clear
      IRB.start(__FILE__)
    end

    desc "serve", "Start an MCP server exposing all project tasks as tools"
    long_desc <<~DESC
      Starts an MCP (Model Context Protocol) server over stdin/stdout.
      Exposes all loaded tasks as tools that Claude CLI or Cursor can call.

      Example — run from project directory:
        frai serve

      Example — run from anywhere with --dir:
        frai serve --dir /path/to/my_project

      Example — connect from Claude CLI:
        claude mcp add my_project -- frai serve --dir /path/to/my_project
    DESC
    option :dir, type: :string, desc: "Path to the Frai project root"
    def serve
      Dir.chdir(options[:dir]) if options[:dir]
      load_project!
      Frai.configuration.adapter ||= :null
      Frai::McpServer.new.run
    end

    desc "exec CLASS_NAME [INPUT]", "Execute a task, pipeline or agent by class name"
    long_desc <<~DESC
      Executes a task, pipeline or agent from the current project.
      Run from inside your project directory.

      CLASS_NAME must match the Ruby class name exactly.
      INPUT is optional — passed as a string to .call.

      Examples:
        frai exec AnalyzeItemTask
        frai exec AnalyzeItemTask "some input text"
        frai exec CompareObjectsPipeline
        frai exec ObjectComparisonAgent "compare a, b, c"
    DESC
    def exec(class_name, input = nil)
      load_project!
      result = Object.const_get(class_name).call(input)
      puts result
    end

    def self.exit_on_failure?
      true
    end

    private

    # Loads the project by requiring config/frai.rb.
    # Aborts with a helpful message if not inside a Frai project.
    def load_project!
      config = File.join(Dir.pwd, "config", "frai.rb")
      abort "Error: config/frai.rb not found. Are you inside a Frai project?" unless File.exist?(config)
      require config
    end
  end
end
