# frozen_string_literal: true

module Frai
  # Validates that all directive files declared in an agent's directives block
  # actually exist on disk, and that no orphan .md.erb files are present.
  #
  # Mirrors StructureChecker for tasks — see that class for the full task logic.
  #
  # @example
  #   Frai::AgentStructureChecker.new(DataAnalysisAgent).check!
  class AgentStructureChecker
    def initialize(agent_class)
      @agent_class  = agent_class
      @agent_name   = agent_class._agent_directive_path
      @project_root = Frai.configuration.project_root
    end

    # Checks all declared directives exist and no orphan files are present.
    # Raises Frai::MissingDirective or Frai::Error on first violation.
    # Returns immediately when no directives block is declared.
    def check!
      declaration = @agent_class.directives
      return unless declaration

      declaration.directive_names.each { |name| find_directive!(name) }
      check_orphan_files!(declaration)
    end

    private

    def find_directive!(name)
      path = File.join(@project_root, "agents", @agent_name, "directives", "#{name}.md.erb")
      return if File.exist?(path)

      raise Frai::MissingDirective,
        "Directive '#{name}' not found for #{@agent_class}.\n" \
        "Expected: agents/#{@agent_name}/directives/#{name}.md.erb"
    end

    def check_orphan_files!(declaration)
      directives_dir = File.join(@project_root, "agents", @agent_name, "directives")
      return unless Dir.exist?(directives_dir)

      Dir.glob(File.join(directives_dir, "*.{md.erb,erb}")).each do |file|
        name = File.basename(file).sub(/\.md\.erb$/, "").sub(/\.erb$/, "").to_sym
        next if declaration.directive_names.include?(name)

        raise Frai::Error,
          "Directive `#{name}` exists in #{directives_dir} but is not declared in #{@agent_class} directives.\n" \
          "Add `directive :#{name}` inside `directives do` or delete the file."
      end
    end
  end
end
