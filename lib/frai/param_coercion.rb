# frozen_string_literal: true

require "json"
require "yaml"

module Frai
  # Parses Hash/Array param values from CLI strings without eval.
  # Tries JSON first, then YAML.safe_load with a strict class allowlist.
  module ParamCoercion
    PERMITTED_YAML_CLASSES = [Hash, Array, String, Integer, Float, TrueClass, FalseClass, NilClass].freeze

    module_function

    # @param str [String]
    # @return [Hash, Array, String] parsed structure or original string
    def parse(str)
      stripped = str.to_s.strip
      return stripped unless structured?(stripped)

      parsed = try_json(stripped) || try_yaml(stripped)
      return parsed if parsed.is_a?(Hash) || parsed.is_a?(Array)

      stripped
    end

    # @param str [String]
    # @param type [Class] Hash or Array
    # @return [Hash, Array, String] coerced value or original string on failure
    def parse_as(str, type)
      stripped = str.to_s.strip
      return stripped unless [Hash, Array].include?(type)
      return stripped unless structured?(stripped)

      parsed = try_json(stripped) || try_yaml(stripped)
      return parsed if parsed.is_a?(type)

      stripped
    end

    # @param str [String]
    def structured?(str)
      str.start_with?("{", "[")
    end

    def try_json(str)
      JSON.parse(str)
    rescue JSON::ParserError
      nil
    end

    def try_yaml(str)
      YAML.safe_load(str, permitted_classes: PERMITTED_YAML_CLASSES, aliases: false)
    rescue StandardError
      nil
    end
    private_class_method :try_json, :try_yaml
  end
end
