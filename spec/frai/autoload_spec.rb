# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Frai.autoload!" do
  subject(:autoload!) { Frai.autoload!(@root) }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      %w[tasks pipelines agents tools].each do |dir|
        FileUtils.mkdir_p(File.join(root, dir))
      end
      example.run
    end
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  context "with valid Ruby class files" do
    before { write("tasks/my_task/task.rb", "MyTaskLoaded = true") }

    it "requires the file" do
      autoload!
      expect(Object.const_defined?(:MyTaskLoaded)).to be true
    end
  end

  context "with a scripts/ folder containing .rb files" do
    before { write("tasks/my_task/scripts/run.rb", "$stdin.read") }

    it "skips the scripts folder without raising" do
      expect { autoload! }.not_to raise_error
    end
  end

  context "with a scripts/ folder nested deeper" do
    before { write("tasks/my_task/scripts/deep/run.rb", "$stdin.read") }

    it "skips nested scripts without raising" do
      expect { autoload! }.not_to raise_error
    end
  end

  context "when a Ruby file outside scripts/ reads from $stdin" do
    let(:bad_file) { write("tasks/bad_task.rb", "$stdin.read") }

    before { bad_file }

    it "raises Frai::Error mentioning the file path and the reason" do
      expect { autoload! }.to raise_error(Frai::Error) do |error|
        expect(error.message).to match(/reads from stdin/)
        expect(error.message).to include(bad_file)
      end
    end
  end

  context "when a Ruby file outside scripts/ reads from STDIN" do
    before { write("tasks/bad_task.rb", "STDIN.read") }

    it "raises Frai::Error" do
      expect { autoload! }.to raise_error(Frai::Error, /reads from stdin/)
    end
  end
end
