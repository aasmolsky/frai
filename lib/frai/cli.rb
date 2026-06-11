# frozen_string_literal: true

require "thor"
require "fileutils"
require "json"
require "erb"
require_relative "setup/mcp"
require_relative "generators/base_generator"
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

    desc "destroy", "Unregister MCP servers and remove client artifacts for this project"
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

    desc "check", "Validate project structure, task contracts, and MCP configurations"
    def check
      load_project!

      errors = []
      task_classes.each do |klass|
        Frai::StructureChecker.new(klass).check!
      rescue Frai::Error => e
        errors << e.message
      end

      agent_classes.each do |klass|
        Frai::AgentStructureChecker.new(klass).check!
      rescue Frai::Error => e
        errors << e.message
      end

      if errors.empty?
        puts "\n  \e[32m✓\e[0m Project is valid. All contracts, directives, scripts, and MCPs are configured correctly.\n\n"
      else
        puts "\n  \e[31m✗\e[0m Project validation failed:\n\n"
        errors.each { |err| puts "    - #{err.gsub("\n", "\n      ")}" }
        abort "\nFound #{errors.size} error(s)."
      end
    end

    desc "list", "List all tasks, MCP servers and shared directives in the project"
    def list
      load_project!

      puts "\nTasks:\n"
      task_classes.each do |klass|
        task      = klass.task_name
        decl      = klass._directive_declaration
        root      = Frai.configuration.project_root
        task_desc = read_directive_desc(root, task, decl&.name || :task)

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

      unless pipeline_classes.empty?
        puts "Pipelines:\n"
        pipeline_classes.each do |klass|
          desc = read_class_desc(klass)
          puts desc ? "  #{klass.name} — #{desc}" : "  #{klass.name}"
        end
        puts
      end

      unless agent_classes.empty?
        puts "Agents:\n"
        agent_classes.each do |klass|
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
      puts
    end

    desc "remove task TASK_NAME", "Remove a task and its slash command (if present)"
    def remove(type, task_name)
      abort "Error: unknown type '#{type}'. Use: task" unless type == "task"
      Frai::Generators::TaskRemover.new(task_name).remove
    end

    desc "exec CLASS_NAME [INPUT]", "Execute a task, pipeline or agent"
    long_desc <<~DESC
      Runs a task from the current project. INPUT can be:
        - a plain string: frai exec AnalyzeItem::Task "some text"
        - key:value pairs: frai exec AnalyzeItem::Task query:hello
        - name(value) format: frai exec AnalyzeItem::Task "query(hello world)"

      Use --log to write output and errors to a file (directories created automatically):
        frai exec AnalyzeItem::Task "query(hello)" --log logs/run.log

      Examples:
        frai exec AnalyzeItem::Task "query(hello world)"
        frai exec AnalyzeItem::Task query:hello
        frai exec SumNumbers::Task "input_numbers(1,2,3)"
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
    rescue StandardError => e
      msg = "Error: #{e.message}"
      log_message(log_path, msg, success: false)
      abort msg
    end

    desc "setup", "Configure external integrations (optional — only for specific clients)"
    long_desc <<~DESC
      Configures third-party clients to use this project's MCP servers and tasks.

      API mode does not need setup — Frai reads mcp/*.rb directly at runtime.

      Targets:
        --claude   Claude CLI: register MCP servers + slash commands for tasks
        --codex    Codex CLI: register MCP servers
        --cursor   Cursor: write .cursor/mcp.json from mcp/*.rb

      Examples:
        frai setup --claude
        frai setup --codex --cursor
    DESC
    option :claude, type: :boolean, desc: "Claude CLI: MCPs + slash commands"
    option :codex,  type: :boolean, desc: "Codex CLI: MCP registration"
    option :cursor, type: :boolean, desc: "Cursor: .cursor/mcp.json"
    def setup
      unless options[:claude] || options[:codex] || options[:cursor]
        abort <<~MSG
          Error: specify a setup target.

            frai setup --claude   # Claude CLI: MCPs + slash commands
            frai setup --codex    # Codex CLI: MCP registration
            frai setup --cursor   # Cursor: .cursor/mcp.json

          Combine targets: frai setup --claude --cursor
        MSG
      end

      load_project!
      servers = Frai::MCP.all

      setup_claude(servers) if options[:claude]
      setup_codex(servers)  if options[:codex]
      setup_cursor(servers) if options[:cursor]
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
                 .select { |k| k < Frai::Task && k.name && k.superclass != Frai::Task }
                 .sort_by(&:name)
    end

    def agent_classes
      ObjectSpace.each_object(Class)
                 .select { |k| k < Frai::Agent && k.name && k.superclass != Frai::Agent }
                 .sort_by(&:name)
    end

    def pipeline_classes
      ObjectSpace.each_object(Class)
                 .select { |k| k < Frai::Pipeline && k.name && k.superclass != Frai::Pipeline }
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

    # Extract # desc: from a Ruby class file (pipeline, agent)
    def read_class_desc(klass)
      path = klass.instance_method(:call).source_location&.first rescue nil
      return nil unless path && File.exist?(path)
      File.foreach(path).first(10).each do |line|
        m = line.match(/^\s*#\s*desc:\s*(.+)/)
        return m[1].strip if m
      end
      nil
    rescue StandardError
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
    rescue StandardError
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
    rescue StandardError
      nil
    end

    def print_list(label, items)
      return if items.empty?
      puts "    #{label}:"
      items.each { |i| puts "      - #{i}" }
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

    def setup_claude(servers)
      if servers.empty?
        puts "  \e[33mskip\e[0m    No MCP servers in mcp/ — skipping MCP registration"
      else
        servers.each { |server| register_mcp_claude(server) }
        verify_client_mcp_registration!("claude", servers)
      end

      allow_mcp_permissions(servers)
      sync_commands

      puts ""
      puts "  \e[32m✓\e[0m Claude CLI setup complete. Restart Claude CLI to apply."
    end

    def setup_codex(servers)
      if servers.empty?
        puts "  \e[33mskip\e[0m    No MCP servers in mcp/ — nothing to register"
      else
        servers.each { |server| register_mcp_codex(server) }
        verify_client_mcp_registration!("codex", servers)
      end

      puts ""
      puts "  \e[32m✓\e[0m Codex CLI setup complete. Restart Codex to apply."
    end

    def setup_cursor(servers)
      if servers.empty?
        puts "  \e[33mskip\e[0m    No MCP servers in mcp/ — nothing to configure"
      else
        sync_cursor_mcp(servers)
      end

      puts ""
      puts "  \e[32m✓\e[0m Cursor setup complete. Reload MCP servers in Cursor settings."
    end

    def verify_client_mcp_registration!(client, servers)
      return if servers.empty?

      registered = Frai::Setup::Mcp.list_client_servers(client)

      servers.each do |server|
        next if Frai::Setup::Mcp.registered?(registered, server.name)

        warn "  \e[33mwarn\e[0m    MCP :#{server.name} is not listed in `#{client} mcp list` — registration may have failed"
      end
    end

    def load_project!
      config = File.join(Dir.pwd, "config", "frai.rb")
      abort "Error: config/frai.rb not found. Are you inside a Frai project?" unless File.exist?(config)
      require config
      load_mcps!
      Frai::StructureChecker.check_mcp_consistency!(Dir.pwd)
      Frai::StructureChecker.check_global_directives_consistency!(Dir.pwd)
    rescue Frai::Error => e
      abort "Error: #{e.message}"
    end

    def allow_mcp_permissions(servers)
      settings_file = File.join(Dir.pwd, ".claude", "settings.local.json")
      FileUtils.mkdir_p(File.dirname(settings_file))
      settings = Frai::Setup::Mcp.parse_json_file(settings_file, label: ".claude/settings.local.json")
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
      Frai::Setup::Commands.sync!(
        root:          Dir.pwd,
        task_classes:  task_classes,
        template_path: File.expand_path("generators/templates/commands/task.md.erb", __dir__)
      )
    end

    def load_mcps!
      Dir[File.join(Dir.pwd, "mcp", "*.rb")].each { |f| require f }
    end

    def register_mcp_claude(server)
      argv = Frai::Setup::Mcp.claude_argv(server)
      return report_skip(argv) if argv.is_a?(Frai::Setup::Mcp::Skip)

      Frai::Setup::Mcp.run_register(argv, server_name: server.name, server_type: server.type)
    end

    def register_mcp_codex(server)
      Frai::Setup::Mcp.codex_notes(server).each do |note|
        puts "  \e[33mnote\e[0m    #{server.name} — #{note}"
      end

      argv = Frai::Setup::Mcp.codex_argv(server)
      return report_skip(argv) if argv.is_a?(Frai::Setup::Mcp::Skip)

      Frai::Setup::Mcp.run_register(argv, server_name: server.name, server_type: server.type)
    end

    def report_skip(skip)
      puts "  \e[33mskip\e[0m    #{skip.server.name} — #{skip.reason}"
    end

    def sync_cursor_mcp(servers)
      root     = Dir.pwd
      mcp_file = File.join(root, ".cursor", "mcp.json")
      existing = Frai::Setup::Mcp.parse_json_file(mcp_file, label: ".cursor/mcp.json")
      state    = Frai::Setup::Mcp.load_state(root)

      managed_before = state["cursor_mcp"] || []
      current_names  = servers.map { |s| s.name.to_s }

      config, configured, skipped = Frai::Setup::Mcp.build_cursor_config(existing, servers)
      skipped.each { |s| report_skip(s) }

      configured.each do |name|
        server = servers.find { |s| s.name.to_s == name }
        Frai::Setup::Mcp.cursor_notes(server).each do |note|
          puts "  \e[33mnote\e[0m    #{server.name} — #{note}"
        end
        puts "  \e[32mconfigure\e[0m #{server.name} (#{server.type})"
      end

      removed = (managed_before - current_names).size
      if configured.empty? && removed.zero?
        puts "  \e[33mskip\e[0m    No MCP servers configured — .cursor/mcp.json unchanged"
        return
      end

      Frai::Setup::Mcp.prune_cursor_orphans!(config, managed_before, current_names)

      FileUtils.mkdir_p(File.dirname(mcp_file))
      File.write(mcp_file, JSON.pretty_generate(config) + "\n")
      puts "  \e[32mupdate\e[0m  .cursor/mcp.json (#{configured.size} configured, #{removed} orphan(s) removed)"

      state["cursor_mcp"] = current_names
      Frai::Setup::Mcp.save_state(root, state)
    end

    # Parses input string into a Hash or returns as-is.
    #
    # Supports:
    #   "key(value) key2(value2)"  → { key: "value", key2: "value2" }
    #   "key({hash}) key2([arr])"  → { key: Hash, key2: Array }  (JSON or YAML)
    #   "key:value key2:value2"    → { key: "value", key2: "value2" }
    #   "plain string"             → "plain string"
    #   nil                        → nil
    def parse_input(input)
      return nil if input.nil? || input.strip.empty?

      # name(value) format — handles nested parens/brackets in values
      if input.strip.match?(/\A\w+\(/)
        pairs = extract_key_value_pairs(input)
        return pairs.each_with_object({}) { |(k, v), h| h[k.to_sym] = coerce_value(v) } unless pairs.empty?
      end

      # key:value format
      if input.match?(/\w+:\S+/)
        pairs = input.scan(/(\w+):(\S+)/)
        return pairs.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      input
    end

    # Extracts key(value) pairs from a string, correctly handling nested
    # parentheses, brackets, and braces inside values.
    def extract_key_value_pairs(input)
      pairs = []
      pos   = 0

      while pos < input.length
        pos += 1 while pos < input.length && input[pos] =~ /\s/
        break if pos >= input.length

        key_match = input[pos..].match(/\A(\w+)\(/)
        break unless key_match

        key       = key_match[1]
        val_start = pos + key.length + 1  # character after opening '('
        depth     = 1
        i         = val_start

        while i < input.length && depth > 0
          case input[i]
          when "(" then depth += 1
          when ")" then depth -= 1
          end
          i += 1 if depth > 0  # don't advance past the outer closing ')'
        end

        pairs << [key, input[val_start...i]]
        pos = i + 1  # skip the closing ')'
      end

      pairs
    end

    def coerce_value(str)
      Frai::ParamCoercion.parse(str)
    end
  end
end
