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

  def write_file(path, content = "")
    full_path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  describe "#check!" do
    context "when no instructions mode is declared" do
      it "does not raise" do
        expect { checker.check! }.not_to raise_error
      end
    end

    context "file mode — instructions" do
      context "when instructions.md.erb is missing" do
        before { agent_class.instructions }

        it "raises MissingDirective with the expected path", :aggregate_failures do
          expect { checker.check! }.to raise_error(Frai::MissingDirective, /Directive 'instructions' not found/)
          expect { checker.check! }.to raise_error(Frai::MissingDirective, %r{agents/review_analysis/directives/instructions\.md\.erb})
        end
      end

      context "when only instructions.md.erb exists" do
        before do
          write_file("agents/review_analysis/directives/instructions.md.erb")
          agent_class.instructions
        end

        it "does not raise" do
          expect { checker.check! }.not_to raise_error
        end
      end

      context "when there is an orphan directive file" do
        before do
          write_file("agents/review_analysis/directives/instructions.md.erb")
          write_file("agents/review_analysis/directives/orphan.md.erb")
          agent_class.instructions
        end

        it "raises an Error with the orphan name and remediation hint", :aggregate_failures do
          expect { checker.check! }.to raise_error(Frai::Error, /Directive `orphan` exists in .* but is not declared/)
          expect { checker.check! }.to raise_error(Frai::Error, /Add `use :orphan` inside `instructions do`/)
        end
      end
    end

    context "inline mode — instructions \"...\"" do
      before { agent_class.instructions "Hardcoded prompt." }

      it "does not raise when directives folder is absent" do
        expect { checker.check! }.not_to raise_error
      end

      it "raises when any directive file exists on disk" do
        write_file("agents/review_analysis/directives/instructions.md.erb")

        expect { checker.check! }.to raise_error(Frai::Error, /unused directive files were found/)
      end
    end

    context "composite mode — instructions do" do
      before do
        agent_class.instructions do
          use :instructions do
            use :guidelines
          end
        end
      end

      context "when a declared directive is missing from disk" do
        it "raises MissingDirective" do
          expect { checker.check! }.to raise_error(Frai::MissingDirective, /Directive 'instructions' not found/)
        end
      end

      context "when all declared directives exist" do
        before do
          write_file("agents/review_analysis/directives/instructions.md.erb")
          write_file("agents/review_analysis/directives/guidelines.md.erb")
        end

        it "does not raise" do
          expect { checker.check! }.not_to raise_error
        end
      end

      context "when there is an orphan directive file" do
        before do
          write_file("agents/review_analysis/directives/instructions.md.erb")
          write_file("agents/review_analysis/directives/guidelines.md.erb")
          write_file("agents/review_analysis/directives/orphan.md.erb")
        end

        it "raises an Error with the orphan name" do
          expect { checker.check! }.to raise_error(Frai::Error, /Directive `orphan` exists in/)
        end
      end
    end
  end

  describe "Frai::Agent::InstructionsBuilder" do
    it "raises when use :entry is missing" do
      expect do
        agent_class.instructions {}
      end.to raise_error(Frai::Error, /must declare `use :entry`/)
    end

    it "raises when more than one top-level use is declared" do
      expect do
        agent_class.instructions do
          use :instructions
          use :other
        end
      end.to raise_error(Frai::Error, /only one top-level `use :entry`/)
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
