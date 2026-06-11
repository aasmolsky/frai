# frozen_string_literal: true

module Frai
  # Declares the structure of a directive: its params, sub-directives, and scripts.
  # Used via the `directive` DSL block in a task class.
  #
  # @example
  #   directive :task do
  #     params do
  #       required :input_numbers, String
  #     end
  #
  #     use :sum do
  #       run :parse_numbers do
  #         input   type: String
  #         returns :parsed_numbers, type: [Integer]
  #       end
  #       run :sum_numbers do
  #         input   type: [Integer]
  #         returns :calculated_sum, type: Integer
  #       end
  #     end
  #
  #     use :high_value do
  #       params { required :calculated_sum, Integer }
  #     end
  #   end
  class DirectiveDeclaration
    # Declares a script's input type and return schema.
    class ScriptDeclaration
      attr_reader :name, :input_type, :input_schema, :returns_schema, :returns_dry_schemas

      def initialize(name, type_resolver: nil)
        @name                = name
        @input_type          = nil
        @input_schema        = nil
        @returns_schema      = {}
        @returns_dry_schemas = {}
        @type_resolver       = type_resolver
      end

      # input type: Hash do             — Hash with dry-schema (required when type: Hash)
      #   required(:key).filled(:type)
      # end
      # input type: String              — scalar type
      # input validate: MySchema        — pre-defined dry-schema for Hash
      def input(type_or_name = nil, type: nil, validate: nil, **_kwargs, &block)
        raise ArgumentError, "input — cannot use both block and validate: together" if block_given? && validate

        if block_given?
          raise ArgumentError,
            "input block requires explicit type: Hash:\n" \
            "  input type: Hash do\n" \
            "    required(:key).filled(:type)\n" \
            "  end" unless type

          resolved = normalize_value(type)
          raise ArgumentError,
            "input block is only supported for type: Hash, got #{resolved}" unless resolved == Hash

          require "dry/schema"
          @input_type   = Hash
          @input_schema = Dry::Schema.define(&block)
        elsif validate
          @input_type   = Hash
          @input_schema = validate
        elsif type
          resolved = normalize_value(type)
          if resolved == Hash
            raise ArgumentError,
              "input type: Hash requires a schema block:\n" \
              "  input type: Hash do\n" \
              "    required(:key).filled(:type)\n" \
              "  end"
          end
          @input_type = resolved
        elsif type_or_name.nil?
          raise ArgumentError, "input requires type: keyword"
        else
          resolved = normalize_value(type_or_name)
          if resolved == Hash
            raise ArgumentError,
              "input type: Hash requires a schema block:\n" \
              "  input type: Hash do\n" \
              "    required(:key).filled(:type)\n" \
              "  end"
          end
          @input_type = resolved
        end
      end

      # returns :name, type: Hash do    — Hash return with dry-schema (required when type: Hash)
      #   required(:key).filled(:type)
      # end
      # returns :name, type: String     — scalar return type
      # returns :name, validate: Schema — pre-defined dry-schema for Hash return
      def returns(schema_or_name = nil, type: nil, validate: nil, &block)
        raise ArgumentError, "returns — cannot use both block and validate: together" if block_given? && validate

        if block_given? && schema_or_name.is_a?(Symbol)
          raise ArgumentError,
            "returns :#{schema_or_name} block requires explicit type: Hash:\n" \
            "  returns :#{schema_or_name}, type: Hash do\n" \
            "    required(:key).filled(:type)\n" \
            "  end" unless type

          resolved = normalize_value(type)
          raise ArgumentError,
            "returns block is only supported for type: Hash, got #{resolved}" unless resolved == Hash

          require "dry/schema"
          dry_schema = Dry::Schema.define(&block)
          @returns_schema[schema_or_name.to_sym]      = Hash
          @returns_dry_schemas[schema_or_name.to_sym] = dry_schema
        elsif validate && schema_or_name.is_a?(Symbol)
          @returns_schema[schema_or_name.to_sym]      = Hash
          @returns_dry_schemas[schema_or_name.to_sym] = validate
        elsif type
          raise ArgumentError, "returns with type: requires a symbol as first arg" unless schema_or_name.is_a?(Symbol)
          resolved = normalize_value(type)
          if resolved == Hash
            raise ArgumentError,
              "returns :#{schema_or_name}, type: Hash requires a schema block:\n" \
              "  returns :#{schema_or_name}, type: Hash do\n" \
              "    required(:key).filled(:type)\n" \
              "  end"
          end
          @returns_schema[schema_or_name.to_sym] = resolved
        elsif block_given?
          raise ArgumentError, "returns block cannot be used with a hash argument" unless schema_or_name.nil?
          builder = ReturnsDeclaration.new(type_resolver: @type_resolver)
          builder.instance_eval(&block)
          @returns_schema = builder.to_h
        else
          @returns_schema = normalize_value(schema_or_name) || {}
        end
      end

      private

      def normalize_value(value)
        case value
        when nil
          nil
        when Array
          value.map { |item| normalize_value(item) }
        when Hash
          value.each_with_object({}) do |(key, nested), hash|
            hash[key.to_sym] = normalize_value(nested)
          end
        when String, Symbol
          return value unless @type_resolver

          @type_resolver.call(value)
        else
          value
        end
      end

      # Declares the fields returned by a script in block form.
      class ReturnsDeclaration
        def initialize(type_resolver:)
          @type_resolver = type_resolver
          @schema = {}
        end

        def to_h
          @schema
        end

        def method_missing(name, *args, &block)
          if block_given?
            raise ArgumentError, "returns field #{name} cannot take both a type and a block" if args.any?

            child = self.class.new(type_resolver: @type_resolver)
            child.instance_eval(&block)
            @schema[name.to_sym] = child.to_h
          else
            raise ArgumentError, "returns field #{name} expects a type" if args.empty?

            @schema[name.to_sym] = normalize_value(args.first)
          end

          self
        end

        def respond_to_missing?(_name, _include_private = false)
          true
        end

        private

        def normalize_value(value)
          case value
          when nil
            nil
          when Array
            value.map { |item| normalize_value(item) }
          when Hash
            value.each_with_object({}) do |(key, nested), hash|
              hash[key.to_sym] = normalize_value(nested)
            end
          when String, Symbol
            return value unless @type_resolver

            @type_resolver.call(value)
          else
            value
          end
        end
      end
    end

    attr_reader :name, :params_declaration, :sub_directives, :script_declarations

    def initialize(name)
      @name                = name
      @params_declaration  = nil
      @sub_directives      = {}
      @script_declarations = {}
    end

    # DSL: declares input params for this directive.
    def params(&block)
      @params_declaration = ParamsDeclaration.new
      @params_declaration.instance_eval(&block)
    end

    # DSL: declares a sub-directive dependency.
    def use(name, &block)
      decl = DirectiveDeclaration.new(name)
      decl.instance_eval(&block) if block_given?
      @sub_directives[name] = decl
    end

    # DSL: declares a script dependency.
    def run(name, type_resolver: nil, &block)
      decl = ScriptDeclaration.new(name, type_resolver: type_resolver)
      decl.instance_eval(&block) if block_given?
      @script_declarations[name] = decl
    end

    # Returns all sub-directive names recursively.
    def all_directive_names
      sub_directives.keys + sub_directives.values.flat_map(&:all_directive_names)
    end

    # Returns all script names recursively.
    def all_script_names
      script_declarations.keys + sub_directives.values.flat_map(&:all_script_names)
    end

    # Returns flat hash of all script declarations across the tree: { name => ScriptDeclaration }
    def all_script_declarations
      sub_directives.values.each_with_object(script_declarations.dup) do |sub, memo|
        memo.merge!(sub.all_script_declarations)
      end
    end
  end
end
