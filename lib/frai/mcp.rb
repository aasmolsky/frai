# frozen_string_literal: true

module Frai
  # Registry of external MCP server definitions required by the project.
  # Declared in mcp/*.rb files.
  #
  # Used for:
  #   1. Registering with Claude CLI/Codex via `frai setup`
  #   2. Passing to RubyLLM as tools in API mode (via ruby_llm-mcp)
  #
  # @example mcp/jira.rb — stdio server
  #   Frai::MCP.define :jira do
  #     command "uv"
  #     args    ["--directory", "~/tools/jira-mcp", "run", "main.py"]
  #     env     JIRA_URL: ENV["JIRA_URL"], JIRA_TOKEN: ENV["JIRA_TOKEN"]
  #   end
  #
  # @example mcp/gitlab.rb — stdio server
  #   Frai::MCP.define :gitlab do
  #     command "uv"
  #     args    ["--directory", "~/tools/gitlab-mcp", "run", "main.py"]
  #     env     GITLAB_TOKEN: ENV["GITLAB_TOKEN"]
  #   end
  module MCP
    class ServerDefinition
      attr_reader :name, :type, :url_value, :command_value, :args_value, :env_value, :oauth_enabled

      def initialize(name)
        @name          = name
        @type          = :stdio
        @url_value     = nil
        @command_value = nil
        @args_value    = []
        @env_value     = {}
        @oauth_enabled = false
      end

      def url(value)
        @type      = :http
        @url_value = value
      end

      def oauth(enabled = true)
        @oauth_enabled = enabled
      end

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
