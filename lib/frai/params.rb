module Frai
  # Holds param declarations for a task directive.
  # Used via the `params` DSL block inside a directive declaration.
  #
  # @example
  #   directive :main do
  #     params do
  #       required :name,     String
  #       required :category, String
  #       optional :lang,     String, default: "en"
  #     end
  #   end
  class ParamsDeclaration
    attr_reader :required_params, :optional_params, :param_schemas

    def initialize
      @required_params = {}  # { name: Type }
      @optional_params = {}  # { name: { type: Type, default: value } }
      @param_schemas   = {}  # { name: schema }
    end

    # Declares a required input param.
    #
    # @param name [Symbol] param name
    # @param type [Class] expected Ruby type (String, Integer, Array, Hash, etc.)
    # @param schema [Hash] optional schema for nested hash validation
    def required(name, type, schema: nil)
      @required_params[name] = type
      @param_schemas[name]   = schema if schema
    end

    # Declares an optional input param with a default value.
    #
    # @param name [Symbol] param name
    # @param type [Class] expected Ruby type
    # @param default [Object] value used when param is not provided
    # @param schema [Hash] optional schema for nested hash validation
    def optional(name, type, default: nil, schema: nil)
      @optional_params[name] = { type: type, default: default }
      @param_schemas[name]   = schema if schema
    end

    # Validates input hash against declared params.
    # Applies defaults for missing optional params.
    # Raises on missing required params or type mismatches.
    #
    # @param input [Hash] input passed to the task
    # @param task_class [Class] used in error messages
    # @return [Hash] input with defaults applied
    def validate!(input, task_class)
      input = input.dup

      required_params.each do |name, type|
        unless input.key?(name)
          raise Frai::MissingParam,
            "required param :#{name} is missing in #{task_class}"
        end

        unless input[name].is_a?(type)
          raise Frai::InvalidParam,
            ":#{name} expected #{type}, got #{input[name].class} in #{task_class}"
        end

        if type == Hash && (schema = @param_schemas[name])
          validate_hash_schema!(input[name], schema, name, task_class)
        end
      end

      optional_params.each do |name, opts|
        if input.key?(name)
          unless input[name].is_a?(opts[:type])
            raise Frai::InvalidParam,
              ":#{name} expected #{opts[:type]}, got #{input[name].class} in #{task_class}"
          end

          if opts[:type] == Hash && (schema = @param_schemas[name])
            validate_hash_schema!(input[name], schema, name, task_class)
          end
        else
          input[name] = opts[:default]
        end
      end

      input
    end

    private

    def validate_hash_schema!(hash, schema, param_name, task_class)
      # dry-schema / dry-validation contract — any object responding to .call
      if schema.respond_to?(:call)
        result = schema.call(hash)
        unless result.success?
          raise Frai::InvalidParam,
            ":#{param_name} validation failed (#{task_class}): #{result.errors.to_h}"
        end
        return
      end

      # Built-in block DSL: { key: Type, ... }
      schema.each do |key, type|
        unless hash.key?(key)
          raise Frai::MissingParam,
            "required key :#{key} missing in :#{param_name} (#{task_class})"
        end
        unless hash[key].is_a?(type)
          raise Frai::InvalidParam,
            ":#{param_name}[:#{key}] expected #{type}, got #{hash[key].class} (#{task_class})"
        end
      end
    end
  end
end
