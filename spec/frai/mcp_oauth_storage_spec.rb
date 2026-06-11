# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::MCP::OAuthStorage do
  let(:project_root) { Dir.mktmpdir }
  let(:storage)      { described_class.new(project_root) }
  let(:server_url)   { "https://remote.example.com/mcp" }

  after { FileUtils.remove_entry(project_root) }

  describe "token persistence" do
    it "stores and reloads tokens via ruby_llm-mcp Auth::Token" do
      token = RubyLLM::MCP::Auth::Token.new(
        access_token:  "tok_123",
        refresh_token: "ref_456",
        expires_in:    3600,
        scope:         "read"
      )

      storage.set_token(server_url, token)

      reloaded = described_class.new(project_root)
      restored = reloaded.get_token(server_url)

      expect(restored.access_token).to eq("tok_123")
      expect(restored.refresh_token).to eq("ref_456")
      expect(restored.scope).to eq("read")
    end
  end

  describe "legacy cache migration" do
    it "migrates the old flat token format" do
      cache_path = File.join(project_root, described_class::CACHE_FILE)
      File.write(cache_path, JSON.generate(
        server_url => {
          "access_token"  => "legacy_tok",
          "refresh_token" => "legacy_ref",
          "expires_at"    => (Time.now.to_i + 3600)
        }
      ))

      restored = described_class.new(project_root).get_token(server_url)
      expect(restored.access_token).to eq("legacy_tok")
    end
  end

  describe "client registration persistence" do
    it "stores client info for token refresh" do
      info = RubyLLM::MCP::Auth::ClientInfo.new(client_id: "client-abc", client_secret: nil)
      storage.set_client_info(server_url, info)

      reloaded = described_class.new(project_root)
      expect(reloaded.get_client_info(server_url).client_id).to eq("client-abc")
    end
  end
end
