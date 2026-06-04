# frozen_string_literal: true

module Frai
  # Base error for all Frai exceptions
  class Error < StandardError; end

  # Raised when a required input param is missing
  class MissingParam < Error; end

  # Raised when an input param has the wrong type
  class InvalidParam < Error; end

  # Raised when a declared directive file does not exist on disk
  class MissingDirective < Error; end

  # Raised when a declared script file does not exist on disk
  class MissingScript < Error; end

  # Raised when a script's output doesn't match its declared returns schema
  class InvalidScriptOutput < Error; end

  # Raised when the LLM adapter is not configured
  class AdapterNotConfigured < Error; end

  # Raised when the configured adapter gem is not installed
  class AdapterNotFound < Error; end
end
