module Frai
  # Registry of MCP (Model Context Protocol) server definitions.
  # Each project declares its own MCP servers in the mcp/ folder.
  # Tasks can only use servers explicitly declared via `mcp :name` in their directive.
  #
  # This ensures full isolation — a task cannot accidentally use a globally
  # configured MCP server that was not declared as a dependency.
  #
  # @example mcp/browser.rb
  #   Frai::MCP.define :browser do
  #     command "npx"
  #     args    ["-y", "@modelcontextprotocol/server-puppeteer"]
  #   end
  #
  # @example mcp/filesystem.rb
  #   Frai::MCP.define :filesystem do
  #     command "npx"
  #     args    ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
  #   end
  module MCP
    # Holds the definition of a single MCP server.
    class ServerDefinition
      attr_reader :name, :command_value, :args_value, :env_value

      def initialize(name)
        @name          = name
        @command_value = nil
        @args_value    = []
        @env_value     = {}
      end

      # The executable to run (e.g. "npx", "python3", "node")
      def command(value)
        @command_value = value
      end

      # Arguments passed to the command
      def args(value)
        @args_value = value
      end

      # Environment variables passed to the MCP server process
      def env(value)
        @env_value = value
      end
    end

    class << self
      # Defines a named MCP server for use in tasks.
      #
      # @param name [Symbol] server name — used in `mcp :name` directive declarations
      # @yield [ServerDefinition]
      def define(name, &block)
        server = ServerDefinition.new(name)
        server.instance_eval(&block) if block_given?
        registry[name] = server
      end

      # Returns a registered server definition by name.
      #
      # @param name [Symbol]
      # @return [ServerDefinition, nil]
      def find(name)
        registry[name]
      end

      # Returns all registered server names.
      #
      # @return [Array<Symbol>]
      def registered
        registry.keys
      end

      # Clears the registry (useful in tests).
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
