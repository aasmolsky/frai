module Frai
  # Represents the declared dependencies of a directive.
  # Built via the `directive` DSL block in a task class.
  #
  # @example
  #   directive :main do
  #     params do
  #       required :input_numbers, String
  #     end
  #
  #     uses :sum do
  #       params do
  #         required :parsed_numbers, Array
  #       end
  #       runs :parse_numbers, with: :input_numbers
  #       runs :add_numbers,   with: :parsed_numbers
  #       returns :calculated_sum, Integer
  #     end
  #
  #     uses :footer do
  #       params do
  #         required :calculated_sum, Integer
  #       end
  #       returns :response, String
  #     end
  #
  #     returns :final_response, String
  #   end
  class DirectiveDeclaration
    # Holds a script declaration: name, with: params, returns: contract
    ScriptDeclaration = Struct.new(:name, :with, :returns)

    # Holds a returns declaration: name and type
    ReturnsDeclaration = Struct.new(:name, :type)

    attr_reader :name,
                :used_directives,
                :script_declarations,
                :used_mcps,
                :params_declaration,
                :sub_declarations,
                :returns_declaration

    def initialize(name)
      @name                = name
      @used_directives     = []
      @script_declarations = []   # [ScriptDeclaration, ...]
      @used_mcps           = []
      @params_declaration  = nil
      @sub_declarations    = {}
      @returns_declaration = nil
    end

    # Declares a dependency on another directive.
    #
    # @param name [Symbol] directive name (maps to directives/<name>.md.erb)
    # @yield optional block for nested dependencies
    def uses(name, &block)
      @used_directives << name
      if block_given?
        sub = DirectiveDeclaration.new(name)
        sub.instance_eval(&block)
        @sub_declarations[name] = sub
      end
    end

    # Declares a script dependency.
    # Script receives only the declared `with:` param as JSON input.
    # After running, result is available in directive as a variable.
    #
    # @param name [Symbol] script name without extension (e.g. :parse_numbers)
    # @param with [Symbol, Array<Symbol>] param(s) passed to the script as input
    # @param returns [Hash] expected output contract e.g. { numbers: Array }
    #
    # @example
    #   runs :parse_numbers, with: :input_numbers, returns: { numbers: Array }
    #   runs :add_numbers,   with: :parsed_numbers, returns: { total: Integer }
    def runs(name, with: nil, returns: nil)
      @script_declarations << ScriptDeclaration.new(name, with, returns)
    end

    # Declares input params for this directive.
    # Validated before any rendering or script execution.
    #
    # @yield [ParamsDeclaration]
    def params(&block)
      @params_declaration = ParamsDeclaration.new
      @params_declaration.instance_eval(&block)
    end

    # Declares what value this directive returns to its caller.
    # Used with use(:name).get(:key) in parent directive templates.
    # Validated after rendering — raises if return_value was not set.
    #
    # @param name [Symbol] return value name
    # @param type [Class] expected Ruby type
    #
    # @example
    #   returns :calculated_sum, Integer
    def returns(name, type)
      @returns_declaration = ReturnsDeclaration.new(name, type)
    end

    # Declares a dependency on an MCP server.
    #
    # @param name [Symbol] MCP server name (maps to mcp/<name>.rb)
    def mcp(name)
      @used_mcps << name
    end

    # Includes a named scheme's dependencies.
    #
    # @param name [Symbol] scheme name declared via `scheme` in the task
    def include_scheme(name)
      @used_directives << { include_scheme: name }
    end

    # Returns all script names (recursive through sub-declarations).
    def all_scripts
      script_declarations.map(&:name) +
        sub_declarations.values.flat_map(&:all_scripts)
    end

    # Returns all directive names (recursive, excluding hashes like include_scheme).
    def all_directives
      dirs = used_directives.reject { |d| d.is_a?(Hash) }
      sub_declarations.each_value { |sub| dirs.concat(sub.all_directives) }
      dirs.uniq
    end

    # Returns all MCP server names (recursive).
    def all_mcps
      mcps = used_mcps.dup
      sub_declarations.each_value { |sub| mcps.concat(sub.all_mcps) }
      mcps.uniq
    end
  end
end
