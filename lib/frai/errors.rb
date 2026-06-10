# frozen_string_literal: true

require "json"

module Frai
  # Base error for all Frai exceptions
  class Error < StandardError; end

  # Raised when a required input param is missing
  class MissingParam < Error; end

  # Raised when an input param has the wrong type
  class InvalidParam < Error; end

  # Raised when a declared directive file does not exist on disk
  class MissingDirective < Error; end

  # Raised when a directive is used in a template but not declared in task definition
  class UndeclaredDirective < Error; end

  # Raised when a declared script file does not exist on disk
  class MissingScript < Error; end

  # Raised when a script is executed in a template but not declared in task definition
  class UndeclaredScript < Error; end

  # Raised when a task omits the required output declaration
  class MissingOutput < Error; end

  # Raised when a script's output doesn't match its declared returns schema
  class InvalidScriptOutput < Error; end

  # Raised when ruby_llm gem is missing but model is configured
  class AdapterNotFound < Error; end

  # Base class for structured LLM output failures.
  # +raw_preview+ is truncated — safe for logs/UI; full raw is not attached.
  class OutputError < Error
    PREVIEW_LIMIT = 500

    attr_reader :raw_preview, :attempt, :task_class

    def initialize(message, raw: nil, attempt: nil, task_class: nil)
      super(message)
      @raw_preview = self.class.preview(raw)
      @attempt     = attempt
      @task_class  = task_class
    end

    class << self
      def preview(raw)
        text = case raw
               when Hash  then JSON.generate(raw)
               when String then raw
               else            raw.inspect
               end

        text = text.to_s.strip
        return text if text.length <= PREVIEW_LIMIT

        "#{text[0, PREVIEW_LIMIT]}… (#{text.length} chars total)"
      rescue StandardError
        "[unpreviewable #{raw.class}]"
      end
    end
  end

  # Raised when an LLM response is not valid JSON object
  class JsonParseError < OutputError; end

  # Raised when parsed JSON fails task output validation
  class ValidationError < OutputError; end

  # Raised when all output retries are exhausted
  class OutputRetriesExhaustedError < OutputError
    attr_reader :last_error, :attempts

    def initialize(last_error, attempts:, task_class:, raw: nil)
      @last_error = last_error
      @attempts   = attempts

      super(
        "Output failed after #{attempts} attempts: #{last_error.message}",
        raw:        raw,
        attempt:    attempts,
        task_class: task_class
      )
    end
  end
end
