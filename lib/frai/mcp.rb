# frozen_string_literal: true

module Frai
  # Registry of external MCP server definitions required by the project.
  # Declared in mcp/*.rb files. Used by `frai setup` to register them
  # with AI clients (Claude CLI, Codex, etc.).
  #
  # @example mcp/jira.rb
  #   Frai::MCP.define :jira do
  #     command "uv"
  #     args    ["--directory", "~/softswiss/jira-mcp", "run", "main.py"]
  #     env     JIRA_URL: ENV["JIRA_URL"], JIRA_TOKEN: ENV["JIRA_TOKEN"]
  #   end
  module MCP
    class ServerDefinition
      attr_reader :name, :type, :url_value, :command_value, :args_value, :env_value

      def initialize(name)
        @name          = name
        @type          = :stdio       # :stdio or :http
        @url_value     = nil
        @command_value = nil
        @args_value    = []
        @env_value     = {}
      end

      # For HTTP MCP servers (streamablehttp)
      def url(value)
        @type      = :http
        @url_value = value
      end

      # For stdio MCP servers
      def command(value)
        @command_value = value
      end

      def args(value)
        @args_value = value
      end

      def env(pairs = {})
        @env_value = pairs.transform_keys(&:to_s)
      end
    end

    class << self
      def define(name, &block)
        server = ServerDefinition.new(name)
        server.instance_eval(&block) if block_given?
        registry[name] = server
      end

      def all
        registry.values
      end

      def find(name)
        registry[name]
      end

      def reset!
        @registry = {}
      end

      private

      def registry
        @registry ||= {}
      end
    end
  end
end
