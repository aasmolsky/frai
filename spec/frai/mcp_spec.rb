# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::MCP do
  after { described_class.reset! }

  describe ".define" do
    it "adds a server definition to the registry" do
      described_class.define(:test_server) do
        desc "A test server"
        command "node"
        args ["index.js"]
      end

      server = described_class.find(:test_server)
      expect(server).to be_a(Frai::MCP::ServerDefinition)
      expect(server.name).to eq(:test_server)
      expect(server.type).to eq(:stdio)
      expect(server.command_value).to eq("node")
      expect(server.args_value).to eq(["index.js"])
      expect(server.description).to eq("A test server")
    end
  end

  describe "ServerDefinition configuration" do
    let(:server) { described_class.find(:configured_server) }

    it "configures stdio type by default" do
      described_class.define(:configured_server) {}
      expect(server.type).to eq(:stdio)
    end

    it "supports configuring http type" do
      described_class.define(:configured_server) do
        url "http://localhost:3000"
      end

      expect(server.type).to eq(:http)
      expect(server.url_value).to eq("http://localhost:3000")
    end

    it "supports configuring oauth" do
      described_class.define(:configured_server) do
        oauth true
      end

      expect(server.oauth_enabled).to be true
    end

    it "supports setting env variables, coercing keys to strings" do
      described_class.define(:configured_server) do
        env MY_VAR: "value", "OTHER" => "thing"
      end

      expect(server.env_value).to eq({ "MY_VAR" => "value", "OTHER" => "thing" })
    end
  end

  describe ".all" do
    it "returns an array of all defined servers" do
      described_class.define(:server_one) {}
      described_class.define(:server_two) {}

      expect(described_class.all.map(&:name)).to contain_exactly(:server_one, :server_two)
    end
  end
end

