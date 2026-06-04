# frozen_string_literal: true

require "json"

module Frai
  # MCP (Model Context Protocol) server that exposes all loaded Frai tasks
  # as tools. Claude CLI or Cursor can connect to it and call tasks directly.
  #
  # Communicates via JSON-RPC 2.0 over stdin/stdout — the standard MCP transport.
  #
  # @example Start the server
  #   Frai::McpServer.new.run
  #
  # @example Connect from Claude CLI
  #   claude mcp add -- my_project frai serve
  class McpServer
    PROTOCOL_VERSION = "2024-11-05"

    def initialize
      $stdout.sync = true
    end

    def run
      $stdin.each_line do |line|
        line = line.strip
        next if line.empty?

        request  = JSON.parse(line)
        response = dispatch(request)
        $stdout.puts(JSON.generate(response)) if response
      end
    rescue Interrupt
      # graceful shutdown
    end

    private

    def dispatch(request)
      id     = request["id"]
      method = request["method"]
      params = request.fetch("params", {})

      case method
      when "initialize"
        result(id, {
          protocolVersion: PROTOCOL_VERSION,
          capabilities:    { tools: {} },
          serverInfo:      { name: "frai", version: Frai::VERSION }
        })
      when "notifications/initialized"
        nil
      when "tools/list"
        result(id, { tools: tools_list })
      when "tools/call"
        call_tool(id, params)
      else
        error(id, -32_601, "Method not found: #{method}")
      end
    rescue => e
      error(request["id"], -32_603, e.message)
    end

    def call_tool(id, params)
      name      = params["name"]
      arguments = params.fetch("arguments", {})

      klass = find_task(name)
      return error(id, -32_602, "Unknown tool: #{name}") unless klass

      unless arguments["_skill"] == klass.task_name
        return error(id, -32_600,
          "Unauthorized: use /#{klass.task_name} skill to call this tool. " \
          "Include _skill: \"#{klass.task_name}\" in your request.")
      end

      input  = arguments.reject { |k, _| k == "_skill" }
      input  = input.empty? ? nil : input.transform_keys(&:to_sym)
      output = klass.call(input)

      result(id, { content: [{ type: "text", text: output.to_s }] })
    rescue Frai::Error => e
      result(id, { content: [{ type: "text", text: "Error: #{e.message}" }], isError: true })
    end

    # --- tools discovery ---

    def tools_list
      task_classes.map do |klass|
        {
          name:        klass.task_name,
          description: "RESTRICTED. Never auto-invoke. Only call when user explicitly uses /#{klass.task_name} skill with param_name(value) format. Calling without explicit user request wastes tokens and is incorrect.",
          inputSchema: input_schema(klass)
        }
      end
    end

    def task_classes
      ObjectSpace.each_object(Class).select do |klass|
        klass < Frai::Task &&
          klass.name &&
          !klass.name.start_with?("Base") &&
          !klass.name.end_with?("Base")
      end
    end

    def find_task(name)
      task_classes.find { |k| k.task_name == name }
    end

    # --- schema helpers ---

    def input_schema(klass)
      decl = klass._directive_declaration
      unless decl&.params_declaration
        return {
          type:       "object",
          properties: {
            "input"  => { type: "string" },
            "_skill" => { type: "string", description: "Must be \"#{@project_name}\". Required for authorization." }
          },
          required: ["_skill"]
        }
      end

      params     = decl.params_declaration
      properties = {}
      required   = []

      params.required_params.each do |name, type|
        properties[name.to_s] = { type: json_type(type) }
        required << name.to_s
      end

      params.optional_params.each do |name, opts|
        properties[name.to_s] = { type: json_type(opts[:type]) }
      end

      properties["_skill"] = { type: "string", description: "Must be \"#{klass.task_name}\". Required for authorization — invoke /#{klass.task_name} skill." }
      required << "_skill"

      schema = { type: "object", properties: properties }
      schema[:required] = required
      schema
    end

    def json_type(ruby_type)
      case ruby_type
      when String  then "string"
      when Integer then "integer"
      when Float   then "number"
      when Array   then "array"
      when Hash    then "object"
      else "string"
      end
    end

    # --- JSON-RPC helpers ---

    def result(id, data)
      { jsonrpc: "2.0", id: id, result: data }
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
  end
end
