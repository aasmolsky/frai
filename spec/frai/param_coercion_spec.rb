# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Frai::ParamCoercion do
  describe ".parse" do
    it "parses JSON objects and arrays" do
      expect(described_class.parse('{"id":"abc"}')).to eq({ "id" => "abc" })
      expect(described_class.parse('["a","b"]')).to eq(%w[a b])
    end

    it "parses YAML flow mappings when JSON fails" do
      expect(described_class.parse("{id: 123}")).to eq({ "id" => 123 })
    end

    it "returns plain strings unchanged" do
      expect(described_class.parse("hello")).to eq("hello")
      expect(described_class.parse("not{json")).to eq("not{json")
    end

    it "does not execute Ruby code" do
      marker = File.join(Dir.tmpdir, "frai_param_coercion_#{Process.pid}")
      FileUtils.rm_f(marker)

      described_class.parse("{system('touch #{marker}')}")

      expect(File).not_to exist(marker)
    end
  end

  describe ".parse_as" do
    it "returns a Hash when type is Hash" do
      expect(described_class.parse_as('{"id":1}', Hash)).to eq({ "id" => 1 })
    end

    it "returns original string when type does not match" do
      expect(described_class.parse_as('["a"]', Hash)).to eq('["a"]')
    end
  end
end
