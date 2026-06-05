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
  #         returns parsed_numbers: [Integer]
  #       end
  #       run :sum_numbers do
  #         input   [Integer]
  #         returns calculated_sum: Integer
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

      def initialize(name)
        @name           = name
        @input_type     = nil
        @returns_schema = {}
      end

      # @param type [Class, Array] expected Ruby type of the input
      def input(type)
        @input_type = type
      end

      # @param schema [Hash] expected return schema e.g. { parsed_numbers: [Integer] }
      def returns(schema)
        @returns_schema = schema
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
    def run(name, &block)
      decl = ScriptDeclaration.new(name)
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
