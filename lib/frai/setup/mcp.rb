# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"

module Frai
  module Setup
    # Pure builders and file sync for `frai setup --claude|--codex|--cursor`.
    # Shell registration uses argv arrays (Open3) — no string interpolation into a shell.
    module Mcp
      Skip = Data.define(:server, :reason)

      STATE_FILE = ".frai/setup_state.json"

      module_function

      def claude_argv(server)
        return skip(server, "URL not set (check your .env)") if server.type == :http && server.url_value.to_s.strip.empty?
        return skip(server, "command not set (check your .env)") if server.type == :stdio && server.command_value.to_s.strip.empty?

        if server.type == :http
          ["claude", "mcp", "add", "--scope", "local", "--transport", "http",
           server.name.to_s, server.url_value]
        else
          env_args  = server.env_value.flat_map { |k, v| ["-e", "#{k}=#{v}"] }
          cmd_parts = stdio_command_parts(server)
          ["claude", "mcp", "add", "--scope", "local", server.name.to_s, *env_args, "--", *cmd_parts]
        end
      end

      def codex_argv(server)
        return skip(server, "URL not set (check your .env)") if server.type == :http && server.url_value.to_s.strip.empty?
        return skip(server, "command not set (check your .env)") if server.type == :stdio && server.command_value.to_s.strip.empty?

        if server.type == :http
          parts = ["codex", "mcp", "add", server.name.to_s, "--url", server.url_value]
          parts += ["--bearer-token-env-var", server.bearer_env_var] if server.bearer_env_var
          parts
        else
          env_args  = server.env_value.flat_map { |k, v| ["--env", "#{k}=#{v}"] }
          cmd_parts = stdio_command_parts(server)
          ["codex", "mcp", "add", server.name.to_s, *env_args, "--", *cmd_parts]
        end
      end

      def codex_notes(server)
        return [] unless server.type == :http && server.oauth_enabled

        ["OAuth: run `codex mcp login #{server.name}` if prompted"]
      end

      def cursor_entry(server)
        return skip(server, "URL not set (check your .env)") if server.type == :http && server.url_value.to_s.strip.empty? && server.url_env_var.nil?
        return skip(server, "command not set (check your .env)") if server.type == :stdio && server.command_value.to_s.strip.empty?

        if server.type == :http
          entry = { "url" => cursor_http_url(server) }
          if server.bearer_env_var
            entry["headers"] = { "Authorization" => "Bearer ${env:#{server.bearer_env_var}}" }
          end
          entry
        else
          cmd_parts = stdio_command_parts(server)
          entry     = { "command" => cmd_parts.first }
          entry["args"] = cmd_parts[1..] if cmd_parts.size > 1
          unless server.env_value.empty?
            entry["env"] = server.env_value.keys.to_h { |k| [k, "${env:#{k}}"] }
          end
          entry
        end
      end

      def cursor_notes(server)
        return [] unless server.type == :http && server.oauth_enabled

        ["OAuth: complete auth in Cursor if prompted"]
      end

      def build_cursor_config(existing, servers)
        config = existing.is_a?(Hash) ? existing.dup : {}
        config["mcpServers"] ||= {}

        configured = []
        skipped    = []

        servers.each do |server|
          entry = cursor_entry(server)
          if entry.is_a?(Skip)
            skipped << entry
            next
          end

          config["mcpServers"][server.name.to_s] = entry
          configured << server.name.to_s
        end

        [config, configured, skipped]
      end

      def prune_cursor_orphans!(config, managed_before, current_names)
        (managed_before - current_names).each do |name|
          config["mcpServers"]&.delete(name)
        end
        config
      end

      def stdio_command_parts(server)
        [server.command_value] + server.args_value.map do |a|
          a.start_with?("~", "/") ? File.expand_path(a) : a
        end
      end

      def run_register(argv, server_name:, server_type:, output: $stdout)
        output.puts "  \e[33mregistering\e[0m #{server_name} (#{server_type})"
        stdout, stderr, status = Open3.capture3(*argv)
        combined = [stdout, stderr].join.strip

        if status.success?
          output.puts "  \e[32m✓\e[0m #{server_name} registered"
          :registered
        elsif combined.match?(/already exists/i)
          output.puts "  \e[32m✓\e[0m #{server_name} already registered"
          :exists
        else
          output.puts "  \e[31mwarn\e[0m    Failed: #{combined}"
          :failed
        end
      end

      def list_client_servers(client)
        stdout, _stderr, status = Open3.capture3(client, "mcp", "list")
        status.success? ? stdout : ""
      end

      def registered?(list_output, server_name)
        list_output.match?(/(?:^|\s)#{Regexp.escape(server_name.to_s)}(?:\s|$)/)
      end

      def parse_json_file(path, label: path)
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Frai::Error, "Invalid #{label}: #{e.message}"
      end

      def load_state(project_root)
        parse_json_file(File.join(project_root, STATE_FILE), label: STATE_FILE)
      end

      def save_state(project_root, state)
        path = File.join(project_root, STATE_FILE)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(state) + "\n")
      end

      def cursor_http_url(server)
        return "${env:#{server.url_env_var}}" if server.url_env_var

        server.url_value
      end

      def skip(server, reason)
        Skip.new(server, reason)
      end
    end
  end
end
