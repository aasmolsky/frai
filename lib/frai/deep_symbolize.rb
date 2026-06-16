# frozen_string_literal: true

module Frai
  # Recursively converts Hash keys to symbols. Arrays are mapped; scalars pass through.
  #
  # Used at LLM boundaries (tool args, JSON responses) so dry-schema contracts
  # that declare +required(:key)+ match string-keyed JSON from providers.
  module DeepSymbolize
    module_function

    def call(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, nested), hash| hash[key.to_sym] = call(nested) }
      when Array
        value.map { |item| call(item) }
      else
        value
      end
    end
  end

  # @param value [Object]
  # @return [Object]
  def self.deep_symbolize(value)
    DeepSymbolize.call(value)
  end
end
