# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Frai::StructureChecker do
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

  let(:task_class) do
    Class.new(Frai::Task) do
      def self.name; "TestTask"; end
      def self.task_name; "test"; end
    end
  end

  subject(:checker) { described_class.new(task_class) }

  def write_file(path)
    full_path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, "")
  end

  describe "#check!" do
    context "when directive tree is missing task" do
      before do
        task_class.class_eval do
          schema { output :text }
        end
      end

      it "raises MissingDirective" do
        expect { checker.check! }.to raise_error(
          Frai::MissingDirective,
          /Directive 'task' not found/
        )
      end
    end

    context "when a sub-directive is missing" do
      before do
        write_file("tasks/test/directives/task.md.erb")
        task_class.class_eval do
          schema do
            use :missing_part
            output :text
          end
        end
      end

      it "raises MissingDirective" do
        expect { checker.check! }.to raise_error(
          Frai::MissingDirective,
          /Directive 'missing_part' not found/
        )
      end
    end

    context "when a script is missing" do
      before do
        write_file("tasks/test/directives/task.md.erb")
        task_class.class_eval do
          schema do
            run :fetch_data do
              input type: String
            end
            output :text
          end
        end
      end

      it "raises MissingScript" do
        expect { checker.check! }.to raise_error(
          Frai::MissingScript,
          /Script 'fetch_data' not found/
        )
      end
    end

    context "when all files exist" do
      before do
        write_file("tasks/test/directives/task.md.erb")
        write_file("tasks/test/directives/header.md.erb")
        write_file("tasks/test/scripts/fetch_data.rb")

        task_class.class_eval do
          schema do
            use :header
            run :fetch_data do
              input type: String
            end
            output :text
          end
        end
      end

      it "does not raise" do
        expect { checker.check! }.not_to raise_error
      end
    end

    context "with an MCP server configured" do
      before do
        write_file("tasks/test/directives/task.md.erb")
        task_class.class_eval do
          schema do
            mcp :gitlab
            output :text
          end
        end
      end

      context "when MCP file is missing" do
        it "raises an Error indicating mcp file is missing" do
          expect { checker.check! }.to raise_error(
            Frai::Error,
            /declares `mcp :gitlab` but mcp\/gitlab\.rb does not exist/
          )
        end
      end

      context "when MCP file exists" do
        before do
          write_file("mcp/gitlab.rb")
        end

        it "does not raise" do
          expect { checker.check! }.not_to raise_error
        end
      end
    end

    context "when there is an orphan directive" do
      before do
        write_file("tasks/test/directives/task.md.erb")
        write_file("tasks/test/directives/orphan.md.erb")
        task_class.class_eval do
          schema do
            output :text
          end
        end
      end

      it "raises an Error indicating the directive is unused" do
        expect { checker.check! }.to raise_error(
          Frai::Error,
          /Directive `orphan` exists in .* but is not declared/
        )
      end
    end

    context "when there is an orphan script" do
      before do
        write_file("tasks/test/directives/task.md.erb")
        write_file("tasks/test/scripts/orphan.rb")
        task_class.class_eval do
          schema do
            output :text
          end
        end
      end

      it "raises an Error indicating the script is unused" do
        expect { checker.check! }.to raise_error(
          Frai::Error,
          /Script `orphan` exists in .* but is not declared/
        )
      end
    end
  end

  describe ".check_global_directives_consistency!" do
    subject(:check!) { described_class.check_global_directives_consistency!(@root) }

    context "when directives/ folder does not exist" do
      it "does not raise" do
        expect { check! }.not_to raise_error
      end
    end

    context "when all global directives are declared by a task" do
      before do
        write_file("directives/shared_context.md.erb")
        task_class.class_eval do
          schema do
            use :shared_context
            output :text
          end
        end
        write_file("tasks/test/directives/task.md.erb")
      end

      it "does not raise" do
        expect { check! }.not_to raise_error
      end
    end

    context "when a global directive is not declared by any task" do
      before do
        write_file("directives/orphan_global.md.erb")
      end

      it "raises an Error indicating the file is unused" do
        expect { check! }.to raise_error(
          Frai::Error,
          /directives\/orphan_global\.md\.erb is defined but never declared in any task/
        )
      end
    end

    context "when a global directive is used as a nested sub-directive" do
      before do
        write_file("directives/deep_shared.md.erb")
        task_class.class_eval do
          schema do
            use :parent_section do
              use :deep_shared
            end
            output :text
          end
        end
        write_file("tasks/test/directives/task.md.erb")
      end

      it "does not raise" do
        expect { check! }.not_to raise_error
      end
    end
  end
end
