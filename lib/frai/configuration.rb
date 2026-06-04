module Frai
  # Holds global Frai configuration.
  # Set via Frai.configure block in config/frai.rb.
  #
  # @example
  #   Frai.configure do |config|
  #     config.adapter = :anthropic
  #     config.model   = "claude-opus-4-6"
  #     config.api_key = ENV["ANTHROPIC_API_KEY"]
  #   end
  class Configuration
    # LLM adapter to use: :anthropic, :openai, :ollama, :null (for testing)
    attr_accessor :adapter

    # Model name passed directly to the provider API
    attr_accessor :model

    # API key for the LLM provider
    attr_accessor :api_key

    # Root directory of the current project (auto-detected)
    attr_accessor :project_root

    def initialize
      @adapter      = nil
      @model        = nil
      @api_key      = nil
      @project_root = Dir.pwd
    end
  end

  class << self
    # Returns the current configuration.
    # @return [Frai::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the configuration object for setup.
    # @yield [Frai::Configuration]
    def configure
      yield configuration
    end

    # Resets configuration to defaults (useful in tests).
    def reset!
      @configuration = Configuration.new
    end

    # Auto-loads all Ruby files from project directories.
    # Skips scripts/ folders entirely — scripts in any language live there
    # and are run directly by ScriptRunner, never required.
    # As an extra guard, raises an error if a Ruby file outside scripts/
    # reads from stdin at the top level.
    #
    # @param root [String] project root directory
    def autoload!(root)
      %w[tasks pipelines agents tools].each do |dir|
        Dir[File.join(root, dir, "**", "*.rb")]
          .reject { |f| f.include?("/scripts/") }
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
