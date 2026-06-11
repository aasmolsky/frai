# frozen_string_literal: true

module Frai
  # Holds global Frai configuration.
  # Set via Frai.configure block in config/frai.rb.
  #
  # @example Without model (CLI mode — prompt returned as-is):
  #   Frai.configure do |config|
  #     config.model = nil
  #   end
  #
  # @example With model (API mode — RubyLLM calls the LLM):
  #   Frai.configure do |config|
  #     config.model   = ENV["LLM_MODEL"]      # e.g. "claude-opus-4-6"
  #     config.api_key = ENV["LLM_API_KEY"]
  #   end
  class Configuration
    VALID_ENVS = %i[development test production].freeze

    # LLM model name. If nil — prompt is returned as-is (CLI mode).
    # If set — RubyLLM calls the provider API with this model.
    attr_accessor :model

    # API key for the LLM provider. Read from ENV["LLM_API_KEY"] by default.
    attr_accessor :api_key

    # Root directory of the current project (auto-detected).
    attr_accessor :project_root

    # Default number of retries after a validation error (0 = one attempt, no retries).
    # Can be overridden per task: output OutputSchema, retries: 2
    attr_accessor :default_retries

    def initialize
      @model           = nil
      @api_key         = nil
      @env             = self.class.coerce_env!(ENV["FRAI_ENV"] || "production")
      @project_root    = Dir.pwd
      @default_retries = 0
    end

    # @param value [String, Symbol]
    def env=(value)
      @env = self.class.coerce_env!(value)
    end

    # @param value [String, Symbol]
    # @return [Symbol]
    # @raise [Frai::Error] when value is not development, test, or production
    def self.coerce_env!(value)
      sym = value.to_sym
      return sym if VALID_ENVS.include?(sym)

      raise Frai::Error,
        "Invalid FRAI_ENV: #{value.inspect}. Use development, test, or production."
    end

    # Project environment (FRAI_ENV). Not affected by agent tool context.
    #
    # | FRAI_ENV       | Task MCPs  | Task LLM (standalone) | Agent LLM |
    # | :development   | skipped    | skipped → prompt      | skipped   |
    # | :test          | skipped    | skipped → prompt      | skipped   |
    # | :production    | connected  | see cli/api mode      | called    |
    #
    # When a task runs as an agent tool (PromptTool/ScriptTool), Task LLM is
    # always skipped — the agent orchestrator calls the LLM instead.
    def env
      @env
    end

    def development?
      @env == :development
    end

    def test?
      @env == :test
    end

    def production?
      @env == :production
    end

    # development / test — inspect prompts and scripts without API or MCP.
    def dry_run?
      development? || test?
    end

    # RSpec isolation — true only in FRAI_ENV=test (not development).
    def non_production?
      test?
    end

    # Task is executing inside Agent.call (PromptTool / ScriptTool).
    # Separate from FRAI_ENV — not a second "production mode".
    def inside_agent_tool?
      Thread.current[:frai_task_context] == :agent_tool
    end

    # CLI mode: production env, no LLM model configured.
    # Frai renders the prompt and returns it — MCP execution is the client's responsibility.
    def cli_mode?
      production? && model.nil?
    end

    # API mode: production env with LLM model configured.
    # Frai calls the LLM API directly; MCPs are attached via ruby_llm-mcp.
    def api_mode?
      production? && !model.nil?
    end
  end

  class << self
    # @return [Frai::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # @yield [Frai::Configuration]
    def configure
      yield configuration
    end

    # Runs a block with a temporary task execution context (e.g. :agent_tool).
    def run_with_task_context(context)
      Thread.current[:frai_task_context] = context
      yield
    ensure
      Thread.current[:frai_task_context] = nil
    end

    # Resets configuration to defaults (useful in tests).
    def reset!
      @configuration = Configuration.new
    end

    # Auto-loads all Ruby files from project directories.
    # Skips scripts/ folders — scripts run as subprocesses, never required.
    # Raises if a Ruby file outside scripts/ reads from stdin at top level.
    #
    # @param root [String] project root directory
    def autoload!(root)
      %w[tasks pipelines agents applications].each do |dir|
        Dir[File.join(root, dir, "**", "*.rb")]
          .reject { |f| f.include?("/scripts/") }
          .sort_by { |f| [f.count(File::SEPARATOR), f] }
          .each do |f|
          if File.foreach(f).any? { |line| line.match?(/^\s*(\$stdin|STDIN)\b/) }
              raise Frai::Error,
                "#{f} reads from stdin at top level — cannot be autoloaded.\n" \
                "Move it to a scripts/ folder."
            end
            require f
          end
      end
    end
  end
end
