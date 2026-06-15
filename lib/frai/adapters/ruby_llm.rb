# frozen_string_literal: true

require "ruby_llm"

module Frai
  module Adapters
    # RubyLLM adapter — sends the rendered prompt to the configured LLM.
    # MCP servers are passed from Task#call and attached as tools.
    class RubyLlm
      def initialize(model)
        @model = model
      end

      # @param prompt [String] rendered prompt
      # @param mcp_servers [Array<Frai::MCP::ServerDefinition>] MCP server definitions
      # @param schema [Class, nil] RubyLLM::Schema class for structured output
      # @return [String, Hash] LLM response — Hash when schema is set
      def complete(prompt, mcp_servers: [], schema: nil)
        require "ruby_llm/mcp"

        chat    = RubyLLM.chat(model: @model)
        clients = attach_mcp_servers(chat, mcp_servers)
        chat    = chat.with_schema(schema) if schema
        result  = chat.ask(prompt).content
        clients.each { |c| c.stop rescue nil }
        result
      rescue LoadError
        chat = RubyLLM.chat(model: @model)
        chat = chat.with_schema(schema) if schema
        chat.ask(prompt).content
      end

      private

      def attach_mcp_servers(chat, servers)
        clients = []

        servers.each do |server|
          client = build_mcp_client(server)
          next unless client

          tools = client.tools
          if tools.empty?
            client.stop rescue nil
            raise Frai::Error,
              "MCP :#{server.name} is not accessible or has no tools.\n" \
              "Check that the server is running and credentials in .env are correct."
          end

          chat.with_tools(*tools)
          clients << client
        rescue Frai::Error
          raise
        rescue => e
          raise Frai::Error,
            "MCP :#{server.name} failed to connect — #{e.message}\n" \
            "Check that the server is installed and .env credentials are set."
        end

        clients
      end

      def build_mcp_client(server)
        case server.type
        when :http  then build_http_client(server)
        when :stdio then build_stdio_client(server)
        end
      end

      def build_http_client(server)
        config = { url: server.url_value }

        if server.oauth_enabled
          storage = oauth_storage
          config[:oauth] = { storage: storage }
        end

        client = RubyLLM::MCP.client(
          name:           server.name.to_s,
          transport_type: :streamable,
          start:          !server.oauth_enabled,
          config:         config
        )

        ensure_oauth!(client, server, storage) if server.oauth_enabled
        client.start unless client.alive?

        client
      rescue Frai::Error
        raise
      rescue => e
        raise Frai::Error,
          "MCP :#{server.name} OAuth failed — #{e.message}\n" \
          "Delete .frai_oauth_cache.json and retry, or run `frai exec` again to re-authenticate."
      end

      def ensure_oauth!(client, server, storage)
        provider = client.oauth(type: :browser, storage: storage)
        return if provider.oauth_provider.access_token

        puts "MCP :#{server.name} requires authentication. Opening browser..."
        provider.authenticate
      end

      def oauth_storage
        @oauth_storage ||= Frai::MCP::OAuthStorage.new(Frai.configuration.project_root)
      end

      def build_stdio_client(server)
        args = server.args_value.map { |a| a.start_with?("~") ? File.expand_path(a) : a }
        RubyLLM::MCP.client(
          name:           server.name.to_s,
          transport_type: :stdio,
          config:         {
            command: server.command_value,
            args:    args,
            env:     server.env_value
          }
        )
      end
    end
  end
end
