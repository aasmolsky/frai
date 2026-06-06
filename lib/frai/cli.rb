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

    desc "list", "List all tasks, MCP servers and shared directives in the project"
    def list
      load_project!

      puts "\nTasks:\n"
      task_classes.each do |klass|
        task      = klass.task_name
        decl      = klass._directive_declaration
        root      = Frai.configuration.project_root
        task_desc = read_directive_desc(root, task, :main)

        params  = format_params(decl&.params_declaration)
        mcps    = klass._mcps.map { |m|
          s = Frai::MCP.find(m)
          "#{m}#{s ? " (#{s.type}#{s.oauth_enabled ? '/oauth' : ''})" : ''}"
        }.join(", ")
        puts "  # #{task_desc}" if task_desc
        puts "  #{task}"
        print_list("params", params_array(decl&.params_declaration))
        print_list("mcp",    klass._mcps.map { |m|
          s = Frai::MCP.find(m)
          "#{m}#{s ? " (#{s.type}#{s.oauth_enabled ? '/oauth' : ''})" : ''}"
        }) unless klass._mcps.empty?
        print_directives(decl, root, task)
        print_scripts(decl, root, task)
        puts
      end

      pipelines = ObjectSpace.each_object(Class)
                             .select { |k| k < Frai::Pipeline && k.name && !k.name.start_with?("Base") }
                             .sort_by(&:name)
      unless pipelines.empty?
        puts "Pipelines:\n"
        pipelines.each do |klass|
          desc = read_class_desc(klass)
          puts desc ? "  #{klass.name} — #{desc}" : "  #{klass.name}"
        end
        puts
      end

      agents = ObjectSpace.each_object(Class)
                          .select { |k| k < Frai::Agent && k.name && !k.name.start_with?("Base") }
                          .sort_by(&:name)
      unless agents.empty?
        puts "Agents:\n"
        agents.each do |klass|
          desc = read_class_desc(klass)
          puts desc ? "  #{klass.name} — #{desc}" : "  #{klass.name}"
        end
        puts
      end

      puts "MCP servers:\n"
      Frai::MCP.all.each do |s|
        transport = s.type.to_s.upcase
        auth      = s.oauth_enabled ? "/oauth" : ""
        location  = s.type == :http ? s.url_value.to_s : "#{s.command_value} #{s.args_value.join(' ')}"
        puts "  # #{s.description}" if s.description
        puts "  - #{s.name}  #{transport}#{auth}"
        puts "      #{location}"
      end

      puts "\nShared directives:\n"
      shared = Dir.glob(File.join(Frai.configuration.project_root, "directives", "*.md.erb"))
      shared.each do |f|
        name = File.basename(f, ".md.erb")
        desc = read_directive_desc(Frai.configuration.project_root, nil, name) rescue nil
        puts "  # #{desc}" if desc
        puts "  - #{name}"
      end
      puts
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

      Use --log to write output and errors to a file (directories created automatically):
        frai exec CodeReviewTask "task_id(PDB-111)" --log logs/reviews.log

      Examples:
        frai exec AnalyzeItemTask "some input"
        frai exec CodeReviewTask task_number:PDB-111
        frai exec SumNumbersTask "input_numbers(1,2,3)"
    DESC
    option :log, type: :string, desc: "Path to log file (created if missing)"
    def exec(class_name, input = nil)
      log_path = options[:log] ? File.expand_path(options[:log], Dir.pwd) : nil
      FileUtils.mkdir_p(File.dirname(log_path)) if log_path

      load_project!
      parsed = parse_input(input)

      klass = begin
        Object.const_get(class_name)
      rescue NameError
        msg = "Error: task class '#{class_name}' not found. Check the class name."
        log_message(log_path, msg, success: false)
        abort msg
      end

      result = klass.call(parsed)
      log_message(log_path, result, success: true) if log_path
      puts result
    rescue Frai::MissingParam, Frai::InvalidParam => e
      klass    = Object.const_get(class_name) rescue nil
      params   = klass&._directive_declaration&.params_declaration
      required = params&.required_params&.keys&.map { |k| "#{k}(value)" }&.join(" ")
      msg = "Error: #{e.message}\n\nUsage: frai exec #{class_name} \"#{required}\""
      log_message(log_path, msg, success: false)
      abort msg
    rescue Frai::Error => e
      msg = "Error: #{e.message}"
      log_message(log_path, msg, success: false)
      abort msg
    rescue => e
      msg = "Error: #{e.message}"
      log_message(log_path, msg, success: false)
      abort msg
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

    map "l"  => "list"
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

    def task_classes
      ObjectSpace.each_object(Class)
                 .select { |k| k < Frai::Task && k.name && !k.name.start_with?("Base") }
                 .sort_by(&:name)
    end

    def params_array(decl)
      return [] unless decl
      required = decl.required_params.map { |n, t| "#{n}(required, #{t})" }
      optional = decl.optional_params.map { |n, o|
        default = o[:default].nil? ? "" : ", default: #{o[:default].inspect}"
        "#{n}(optional, #{o[:type]}#{default})"
      }
      required + optional
    end

    def format_params(decl)
      params_array(decl).join(", ")
    end

    def format_directives(decl)
      return "" unless decl
      decl.sub_directives.keys.map(&:to_s).join(", ")
    end

    def print_directives(decl, root, task_name)
      return unless decl
      dirs = decl.sub_directives.keys
      return if dirs.empty?
      puts "    directives:"
      dirs.each do |name|
        desc = read_directive_desc(root, task_name, name)
        puts "      # #{desc}" if desc
        puts "      - #{name}"
      end
    end

    def format_scripts(decl)
      return "" unless decl
      collect_scripts(decl).map(&:to_s).join(", ")
    end

    # Extract # desc: from a Ruby class file (pipeline, agent)
    def read_class_desc(klass)
      path = klass.instance_method(:call).source_location&.first rescue nil
      return nil unless path && File.exist?(path)
      File.foreach(path).first(10).each do |line|
        m = line.match(/^\s*#\s*desc:\s*(.+)/)
        return m[1].strip if m
      end
      nil
    rescue
      nil
    end

    # Extract <desc>...</desc> from a directive template
    def read_directive_desc(root, task_name, directive_name)
      candidates = task_name ? [
        File.join(root, "tasks", task_name, "directives", "#{directive_name}.md.erb"),
        File.join(root, "tasks", task_name, "directives", "#{directive_name}.erb")
      ] : []
      candidates += [File.join(root, "directives", "#{directive_name}.md.erb")]
      path = candidates.find { |p| File.exist?(p) }
      return nil unless path
      content = File.read(path)
      m = content.match(/<desc>(.*?)<\/desc>/m)
      m ? m[1].strip : nil
    rescue
      nil
    end

    # Extract # desc: from a script file
    def read_script_desc(path)
      return nil unless File.exist?(path)
      File.foreach(path).first(5).each do |line|
        m = line.match(/^\s*#\s*desc:\s*(.+)/)
        return m[1].strip if m
      end
      nil
    rescue
      nil
    end

    def print_list(label, items)
      return if items.empty?
      puts "    #{label}:"
      items.each { |i| puts "      - #{i}" }
    end

    def print_scripts(decl, root, task_name)
      return unless decl
      names = collect_scripts(decl)
      return if names.empty?
      puts "    scripts:"
      names.each do |n|
        script_path = Dir.glob(File.join(root, "tasks", task_name, "scripts", "#{n}.*")).first
        desc = script_path ? read_script_desc(script_path) : nil
        puts "      # #{desc}" if desc
        puts "      - #{n}"
      end
    end

    def collect_scripts(decl)
      names = decl.script_declarations.keys
      decl.sub_directives.each_value { |sub| names += collect_scripts(sub) }
      names.uniq
    end

    def log_message(path, message, success:)
      return unless path
      timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      status    = success ? "SUCCESS" : "ERROR"
      File.open(path, "a") do |f|
        f.puts "[#{timestamp}] [#{status}]"
        f.puts message
        f.puts "-" * 60
      end
    end

    def load_project!
      config = File.join(Dir.pwd, "config", "frai.rb")
      abort "Error: config/frai.rb not found. Are you inside a Frai project?" unless File.exist?(config)
      require config
      load_mcps!
      Frai::StructureChecker.check_mcp_consistency!(Dir.pwd)
    rescue Frai::Error => e
      abort "Error: #{e.message}"
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
