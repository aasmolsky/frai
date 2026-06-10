# frozen_string_literal: true

require "json"

module Frai
  # Normalizes LLM structured output to a validated Hash.
  #
  # Primary path: ruby_llm + with_schema returns a Hash — we symbolize keys only.
  # Fallback string parsing is optional and disabled in strict mode (default).
  class JsonResponse
    TRAILING_COMMA = /,(\s*[}\]])/

    class << self
      # @param content [Hash, String] ruby_llm response (.content)
      # @param validate [Proc, Symbol, nil] validate.call(data, context) or validate!(data, context) on receiver
      # @param validator_receiver [Object, nil] when set, Symbol/Proc validators run on this object
      # @param context [Hash] task input params
      # @param strict [Boolean] when true, no trailing-comma repair; single JSON.parse for strings
      # @param attempt [Integer, nil] 1-based attempt number for error metadata
      # @param task_class [Class, nil] task class for error metadata
      # @return [Hash]
      def normalize(content, validate: nil, validator_receiver: nil, context: {}, strict: true,
                    attempt: nil, task_class: nil)
        data = coerce_to_hash(content, strict: strict, attempt: attempt, task_class: task_class)
        run_validator!(
          validate,
          data,
          context,
          raw:                content,
          attempt:            attempt,
          task_class:         task_class,
          validator_receiver: validator_receiver
        )
        data
      end

      # Strip markdown fences and surrounding whitespace.
      def clean(raw)
        raw.to_s
            .gsub(/\A\s*```(?:json)?\s*/i, "")
            .gsub(/\s*```\s*\z/, "")
            .strip
      end

      def run_validator!(validate, data, context, raw:, attempt:, task_class:, validator_receiver: nil)
        return unless validate

        if validator_receiver
          case validate
          when Symbol
            validator_receiver.send(validate, data, context)
          when Proc
            validator_receiver.instance_exec(data, context, &validate)
          else
            raise ValidationError.new(
              "unsupported validate type #{validate.class}",
              raw: raw, attempt: attempt, task_class: task_class
            )
          end
        else
          validate.call(data, context)
        end
      rescue ValidationError
        raise
      rescue StandardError => e
        raise ValidationError.new(
          "output validator raised #{e.class}: #{e.message}",
          raw:        raw,
          attempt:    attempt,
          task_class: task_class
        )
      end

      private

      def coerce_to_hash(content, strict:, attempt:, task_class:)
        case content
        when Hash
          symbolize_keys(content)
        when String
          parse_string!(content, strict: strict, attempt: attempt, task_class: task_class)
        else
          raise parse_error(
            "expected Hash or JSON String, got #{content.class}",
            raw: content, attempt: attempt, task_class: task_class
          )
        end
      end

      def parse_string!(raw, strict:, attempt:, task_class:)
        cleaned = clean(raw)
        data    = if strict
                    JSON.parse(cleaned, symbolize_names: true)
                  else
                    parse_lenient(cleaned)
                  end

        unless data.is_a?(Hash)
          raise parse_error(
            "expected JSON object, got #{data.class}",
            raw: raw, attempt: attempt, task_class: task_class
          )
        end

        data
      rescue JSON::ParserError => e
        raise parse_error(
          "invalid JSON: #{e.message}",
          raw: raw, attempt: attempt, task_class: task_class
        )
      end

      def parse_lenient(cleaned)
        JSON.parse(cleaned, symbolize_names: true)
      rescue JSON::ParserError
        fixed = cleaned.gsub(TRAILING_COMMA, '\1')
        JSON.parse(fixed, symbolize_names: true)
      end

      def parse_error(message, raw:, attempt:, task_class:)
        JsonParseError.new(message, raw: raw, attempt: attempt, task_class: task_class)
      end

      def symbolize_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), hash|
            hash[key.to_sym] = symbolize_keys(nested)
          end
        when Array
          value.map { |item| symbolize_keys(item) }
        else
          value
        end
      end
    end
  end
end
