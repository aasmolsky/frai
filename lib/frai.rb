# frozen_string_literal: true

# Foundation
require_relative "frai/version"
require_relative "frai/errors"
require_relative "frai/configuration"

# Input / schema primitives
require_relative "frai/params"
require_relative "frai/param_coercion"
require_relative "frai/directive_declaration"

# Structure validation
require_relative "frai/structure_checker"
require_relative "frai/agent_structure_checker"

# Runtime — rendering and script execution
require_relative "frai/script_runner"
require_relative "frai/directive_renderer"

# MCP
require_relative "frai/mcp"
require_relative "frai/mcp_oauth_storage"
require_relative "frai/setup/mcp"
require_relative "frai/setup/commands"

# Adapters — null always loaded; ruby_llm loaded lazily when model is configured
require_relative "frai/llm"
require_relative "frai/adapters/null"
require_relative "frai/json_response"

# Domain objects
require_relative "frai/task"
require_relative "frai/pipeline"
require_relative "frai/agent"

# Tools (used by agents to call tasks as prompt generators)
require_relative "frai/prompt_tool"
require_relative "frai/script_tool"

# Public entrypoint base class
require_relative "frai/application"
