# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::Setup::Mcp do
  after { Frai::MCP.reset! }

  def define_server(name, &block)
    Frai::MCP.define(name, &block)
    Frai::MCP.find(name)
  end

  describe ".claude_argv" do
    it "builds stdio argv with env and expanded paths" do
      server = define_server(:database) do
        command "node"
        args    ["~/tools/server.js"]
        env     TOKEN: "secret"
      end

      argv = described_class.claude_argv(server)
      expect(argv).to eq([
        "claude", "mcp", "add", "--scope", "local", "database",
        "-e", "TOKEN=secret", "--", "node", File.expand_path("~/tools/server.js")
      ])
    end

    it "builds http argv" do
      server = define_server(:remote_service) { url "https://mcp.example.com" }

      expect(described_class.claude_argv(server)).to eq([
        "claude", "mcp", "add", "--scope", "local", "--transport", "http",
        "remote_service", "https://mcp.example.com"
      ])
    end

    it "returns Skip when url is missing" do
      server = define_server(:remote_service) { url "" }
      result = described_class.claude_argv(server)

      expect(result).to be_a(described_class::Skip)
      expect(result.reason).to include("URL not set")
    end
  end

  describe ".codex_argv" do
    it "adds bearer-token-env-var when bearer_env is declared" do
      server = define_server(:api_gateway) do
        url        "https://api.example.com/mcp"
        bearer_env "GATEWAY_TOKEN"
      end

      expect(described_class.codex_argv(server)).to eq([
        "codex", "mcp", "add", "api_gateway", "--url", "https://api.example.com/mcp",
        "--bearer-token-env-var", "GATEWAY_TOKEN"
      ])
    end

    it "does not infer bearer from env hash" do
      server = define_server(:api_gateway) do
        url "https://api.example.com/mcp"
        env GATEWAY_TOKEN: "x", OTHER: "y"
      end

      argv = described_class.codex_argv(server)
      expect(argv).not_to include("--bearer-token-env-var")
    end
  end

  describe ".cursor_entry" do
    it "uses url_env for Cursor HTTP URL" do
      server = define_server(:remote_service) do
        url     "https://resolved.example.com"
        url_env "REMOTE_MCP_URL"
      end

      expect(described_class.cursor_entry(server)).to eq({ "url" => "${env:REMOTE_MCP_URL}" })
    end

    it "uses bearer_env for Authorization header" do
      server = define_server(:api_gateway) do
        url        "https://api.example.com/mcp"
        bearer_env "GATEWAY_TOKEN"
      end

      expect(described_class.cursor_entry(server)).to eq({
        "url" => "https://api.example.com/mcp",
        "headers" => { "Authorization" => "Bearer ${env:GATEWAY_TOKEN}" }
      })
    end

    it "uses env refs for stdio subprocess" do
      server = define_server(:database) do
        command "npx"
        args    ["-y", "server"]
        env     DATABASE_URL: "postgres://local"
      end

      expect(described_class.cursor_entry(server)).to eq({
        "command" => "npx",
        "args" => ["-y", "server"],
        "env" => { "DATABASE_URL" => "${env:DATABASE_URL}" }
      })
    end
  end

  describe ".build_cursor_config" do
    it "merges configured servers and reports skips" do
      ok = define_server(:database) { command "node" }
      bad = define_server(:broken) { url "" }

      config, configured, skipped = described_class.build_cursor_config({}, [ok, bad])

      expect(configured).to eq(["database"])
      expect(skipped.size).to eq(1)
      expect(config.dig("mcpServers", "database", "command")).to eq("node")
      expect(config["mcpServers"]).not_to have_key("broken")
    end
  end

  describe ".prune_cursor_orphans!" do
    it "removes servers no longer in mcp/*.rb" do
      config = { "mcpServers" => { "database" => {}, "legacy" => {} } }
      described_class.prune_cursor_orphans!(config, %w[database legacy], %w[database])

      expect(config["mcpServers"].keys).to eq(["database"])
    end

    it "does not remove user-added servers" do
      config = { "mcpServers" => { "database" => {}, "my_custom" => {} } }
      described_class.prune_cursor_orphans!(config, %w[database], %w[database])

      expect(config["mcpServers"].keys).to contain_exactly("database", "my_custom")
    end
  end

  describe ".registered?" do
    it "matches whole server names" do
      list = "database (stdio)\nmy_database_backup (http)\n"
      expect(described_class.registered?(list, :database)).to be true
      expect(described_class.registered?(list, :my)).to be false
    end
  end

  describe ".parse_json_file" do
    it "raises Frai::Error on invalid JSON" do
      path = File.join(Dir.tmpdir, "frai_bad_#{Process.pid}.json")
      File.write(path, "not json")

      expect {
        described_class.parse_json_file(path, label: "test.json")
      }.to raise_error(Frai::Error, /Invalid test.json/)
    ensure
      File.delete(path) if File.exist?(path)
    end
  end
end
