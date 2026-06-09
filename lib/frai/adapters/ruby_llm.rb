require "ruby_llm"

module Frai
  module Adapters
    # RubyLLM adapter — sends the rendered prompt to the configured LLM.
    # MCP servers are passed from Task#call and attached as tools.
    class RubyLlm
      def initialize(model, api_key)
        @model = model
        configure_provider(model, api_key)
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

      def configure_provider(model, api_key)
        key = api_key.to_s.strip
        raise Frai::Error, "LLM_API_KEY is not set" if key.empty?

        RubyLLM.configure do |c|
          case model.to_s
          when /\Agpt/, /\Ao1/, /\Ao3/, /\Atext-/ then c.openai_api_key    = key
          when /\Aclaude/                          then c.anthropic_api_key = key
          when /\Agemini/                          then c.gemini_api_key    = key
          when /\Amistral/                         then c.mistral_api_key   = key
          else                                          c.openai_api_key    = key
          end
        end
      end

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
        when :http
          build_http_client(server)
        when :stdio
          build_stdio_client(server)
        end
      rescue Frai::Error
        raise
      rescue => e
        raise Frai::Error,
          "MCP :#{server.name} failed to connect — #{e.message}"
      end

      def build_http_client(server)
        if server.oauth_enabled
          build_oauth_http_client(server)
        else
          RubyLLM::MCP.client(
            name:           server.name.to_s,
            transport_type: :streamable,
            config:         { url: server.url_value }
          )
        end
      end

      def build_oauth_http_client(server)
        cache       = Frai::MCPTokenCache.new(Frai.configuration.project_root)
        access_token = cache.fresh_access_token(server.url_value)

        if access_token
          # Use cached/refreshed token — inject as Authorization header
          RubyLLM::MCP.client(
            name:           server.name.to_s,
            transport_type: :streamable,
            config:         {
              url:     server.url_value,
              headers: { "Authorization" => "Bearer #{access_token}" }
            }
          )
        else
          # No valid token — do browser OAuth flow
          puts "MCP :#{server.name} requires authentication. Opening browser..."
          temp = RubyLLM::MCP.client(
            name:           "#{server.name}_auth",
            transport_type: :streamable,
            start:          false,
            config:         { url: server.url_value }
          )
          provider = temp.oauth(type: :browser)
          token    = provider.authenticate
          data     = cache.save(server.url_value, token)

          RubyLLM::MCP.client(
            name:           server.name.to_s,
            transport_type: :streamable,
            config:         {
              url:     server.url_value,
              headers: { "Authorization" => "Bearer #{data['access_token']}" }
            }
          )
        end
      rescue Frai::Error
        raise
      rescue => e
        raise Frai::Error,
          "MCP :#{server.name} OAuth failed — #{e.message}\n" \
          "Run `frai c` and authenticate manually."
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
