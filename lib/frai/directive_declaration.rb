# frozen_string_literal: true

module Frai
  # Declares the structure of a directive: its params, sub-directives, and scripts.
  # Used via the `directive` DSL block in a task class.
  #
  # @example
  #   directive :main do
  #     params do
  #       required :input_numbers, String
  #     end
  #
  #     use :sum do
  #       run :parse_numbers do
  #         input   String
  #         returns do
  #           parsed_numbers [Integer]
  #         end
  #       end
  #       run :sum_numbers do
  #         input   [Integer]
  #         returns do
  #           calculated_sum Integer
  #         end
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
      attr_reader :name, :input_type, :returns_schema

      def initialize(name, type_resolver: nil)
        @name           = name
        @input_type     = nil
        @returns_schema = {}
        @type_resolver  = type_resolver
      end

      # @param type [Class, Array] expected Ruby type of the input
      def input(type)
        @input_type = normalize_value(type)
      end

      # @param schema [Hash] expected return schema e.g. { parsed_numbers: [Integer] }
      def returns(schema = nil, &block)
        if block_given?
          raise ArgumentError, "returns accepts either a hash or a block, not both" unless schema.nil?

          builder = ReturnsDeclaration.new(type_resolver: @type_resolver)
          builder.instance_eval(&block)
          @returns_schema = builder.to_h
        else
          @returns_schema = normalize_value(schema) || {}
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
  end
end
