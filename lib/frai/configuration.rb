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
    # LLM model name. If nil — prompt is returned as-is (CLI mode).
    # If set — RubyLLM calls the provider API with this model.
    attr_accessor :model

    # API key for the LLM provider. Read from ENV["LLM_API_KEY"] by default.
    attr_accessor :api_key

    # Environment: :development or :production (default).
    # In development: OAuth MCP servers are skipped with a warning.
    attr_accessor :env

    # Root directory of the current project (auto-detected).
    attr_accessor :project_root

    def initialize
      @model        = nil
      @api_key      = nil
      @env          = (ENV["FRAI_ENV"] || "production").to_sym
      @project_root = Dir.pwd
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

    # Both development and test skip MCPs and LLM calls
    def non_production?
      development? || test?
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
      %w[tasks pipelines agents].each do |dir|
        Dir[File.join(root, dir, "**", "*.rb")]
          .reject { |f| f.include?("/scripts/") }
          .sort_by { |f| [f.count(File::SEPARATOR), f] }
          .each do |f|
            if File.read(f).match?(/^\s*(\$stdin|STDIN)\b/)
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
