require "frai"

# Load environment variables from .env (project-local, git-ignored)
env_file = File.join(__dir__, "..", ".env")
if File.exist?(env_file)
  File.foreach(env_file) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    ENV[key] ||= value.to_s.strip
  end
end

# Auto-load all Ruby files from the project directories.
Frai.autoload!(File.expand_path("..", __dir__))

Frai.configure do |config|
  # LLM model — if set, frai calls the API via RubyLLM.
  # If nil, frai returns the rendered prompt (CLI mode — Claude CLI is the LLM).
  #
  # config.model   = ENV["LLM_MODEL"]   # e.g. "claude-opus-4-6", "gpt-4o"
  # config.api_key = ENV["API_KEY"]
end
