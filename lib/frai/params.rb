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
    attr_reader :required_params, :optional_params

    def initialize
      @required_params = {}  # { name: Type }
      @optional_params = {}  # { name: { type: Type, default: value } }
    end

    # Declares a required input param.
    #
    # @param name [Symbol] param name
    # @param type [Class] expected Ruby type (String, Integer, Array, Hash, etc.)
    def required(name, type)
      @required_params[name] = type
    end

    # Declares an optional input param with a default value.
    #
    # @param name [Symbol] param name
    # @param type [Class] expected Ruby type
    # @param default [Object] value used when param is not provided
    def optional(name, type, default: nil)
      @optional_params[name] = { type: type, default: default }
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
      end

      optional_params.each do |name, opts|
        if input.key?(name)
          unless input[name].is_a?(opts[:type])
            raise Frai::InvalidParam,
              ":#{name} expected #{opts[:type]}, got #{input[name].class} in #{task_class}"
          end
        else
          input[name] = opts[:default]
        end
      end

      input
    end
  end
end
