# frozen_string_literal: true

module Frai
  # Registry of external MCP server definitions required by the project.
  # Declared in mcp/*.rb files.
  #
  # Used for:
  #   1. Passing to RubyLLM as tools in API mode (via ruby_llm-mcp)
  #   2. Registering with optional clients via `frai setup --claude|--codex|--cursor`
  #
  # @example mcp/database.rb — stdio server
  #   Frai::MCP.define :database do
  #     desc    "Database access"
  #     command "npx"
  #     args    ["-y", "@modelcontextprotocol/server-postgres", ENV["DATABASE_URL"]]
  #     env     DATABASE_URL: ENV["DATABASE_URL"]
  #   end
  #
  # @example mcp/remote_service.rb — HTTP with OAuth
  #   Frai::MCP.define :remote_service do
  #     url     ENV["REMOTE_MCP_URL"]
  #     url_env "REMOTE_MCP_URL"
  #     oauth   true
  #   end
  #
  # @example mcp/api_gateway.rb — HTTP with bearer token
  #   Frai::MCP.define :api_gateway do
  #     url        ENV["GATEWAY_MCP_URL"]
  #     bearer_env "GATEWAY_TOKEN"
  #   end
  module MCP
    class ServerDefinition
      attr_reader :name, :type, :url_value, :url_env_var, :command_value, :args_value,
                  :env_value, :oauth_enabled, :bearer_env_var, :description

      def initialize(name)
        @name            = name
        @type            = :stdio
        @url_value       = nil
        @url_env_var     = nil
        @command_value   = nil
        @args_value      = []
        @env_value       = {}
        @oauth_enabled   = false
        @bearer_env_var  = nil
        @description     = nil
      end

      def desc(text)
        @description = text
      end

      def url(value)
        @type      = :http
        @url_value = value
      end

      def oauth(enabled = true)
        @oauth_enabled = enabled
      end

      # Env var name for streamable HTTP bearer auth (Codex/Cursor setup).
      def bearer_env(name)
        @bearer_env_var = name.to_s
      end

      # Env var name for HTTP URL in Cursor setup (${env:NAME}).
      def url_env(name)
        @url_env_var = name.to_s
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
