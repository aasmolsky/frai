# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Frai::AgentStructureChecker do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      Frai.configure do |config|
        config.project_root = root
      end
      example.run
    end
  end

  let(:agent_class) do
    Class.new(Frai::Agent) do
      def self.name; "ReviewAnalysisAgent"; end
    end
  end

  subject(:checker) { described_class.new(agent_class) }

  def write_file(path)
    full_path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, "")
  end

  describe "#check!" do
    context "when no directives block is declared" do
      it "does not raise" do
        expect { checker.check! }.not_to raise_error
      end
    end

    context "when a declared directive is missing from disk" do
      before do
        agent_class.directives do
          directive :instructions
        end
      end

      it "raises MissingDirective with the expected path", :aggregate_failures do
        expect { checker.check! }.to raise_error(Frai::MissingDirective, /Directive 'instructions' not found/)
        expect { checker.check! }.to raise_error(Frai::MissingDirective, %r{agents/review_analysis/directives/instructions\.md\.erb})
      end
    end

    context "when all declared directives exist" do
      before do
        write_file("agents/review_analysis/directives/instructions.md.erb")
        write_file("agents/review_analysis/directives/tool_descriptions.md.erb")

        agent_class.directives do
          directive :instructions
          directive :tool_descriptions
        end
      end

      it "does not raise" do
        expect { checker.check! }.not_to raise_error
      end
    end

    context "when there is an orphan directive file not declared in directives" do
      before do
        write_file("agents/review_analysis/directives/instructions.md.erb")
        write_file("agents/review_analysis/directives/orphan.md.erb")

        agent_class.directives do
          directive :instructions
        end
      end

      it "raises an Error with the orphan name and remediation hint", :aggregate_failures do
        expect { checker.check! }.to raise_error(Frai::Error, /Directive `orphan` exists in .* but is not declared/)
        expect { checker.check! }.to raise_error(Frai::Error, /Add `directive :orphan` inside `directives do`/)
      end
    end

    context "when directives folder does not exist and directives block is empty" do
      before { agent_class.directives {} }

      it "does not raise" do
        expect { checker.check! }.not_to raise_error
      end
    end
  end

  describe "Frai::Agent::DirectivesDeclaration" do
    it "raises when the same directive is declared twice" do
      expect do
        agent_class.directives do
          directive :instructions
          directive :instructions
        end
      end.to raise_error(Frai::Error, /directive :instructions already declared/)
    end
  end

  describe "agent_directive_path derivation" do
    it "converts ReviewAnalysisAgent → review_analysis" do
      expect(agent_class._agent_directive_path).to eq("review_analysis")
    end

    it "converts a simple name like SupportAgent → support" do
      klass = Class.new(Frai::Agent) { def self.name; "SupportAgent"; end }
      expect(klass._agent_directive_path).to eq("support")
    end
  end
end
