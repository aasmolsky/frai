# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "frai/generators/new_generator"

RSpec.describe Frai::Generators::NewGenerator do
  around do |example|
    original = ENV["FRAI_GEM_PATH"]
    example.run
    ENV["FRAI_GEM_PATH"] = original
  end

  def generate_in_tmp(name)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        capture_stdout { described_class.new(name).generate }
        yield File.read(File.join(dir, name, "Gemfile"))
      end
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  it "writes a Gemfile that pins the frai version" do
    ENV.delete("FRAI_GEM_PATH")
    generate_in_tmp("ai") do |gemfile|
      expect(gemfile).to include(%(gem "frai", "~> #{Frai::VERSION}"))
    end
  end

  it "uses a local path when FRAI_GEM_PATH is set" do
    ENV["FRAI_GEM_PATH"] = "/tmp/frai-local"
    generate_in_tmp("ai") do |gemfile|
      expect(gemfile).to include(%(gem "frai", path: "/tmp/frai-local"))
    end
  end
end
