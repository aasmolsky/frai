# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Frai
  # Persistent OAuth token cache for MCP servers.
  # Handles silent token refresh using refresh_token.
  class MCPTokenCache
    CACHE_FILE = ".frai_oauth_cache.json"

    def initialize(project_root)
      @path = File.join(project_root, CACHE_FILE)
      ensure_gitignored
    end

    # Returns a fresh access_token for the given server_url.
    # Tries silent refresh if expired. Returns nil if re-auth needed.
    def fresh_access_token(server_url)
      data = load[server_url]
      return nil unless data

      expires_at = data["expires_at"].to_i
      if Time.now.to_i < expires_at - 30
        # Token still valid
        data["access_token"]
      else
        # Try silent refresh
        refresh(server_url, data)
      end
    end

    # Save token data after successful auth.
    def save(server_url, token)
      all = load
      all[server_url] = {
        "access_token"  => token.instance_variable_get(:@access_token),
        "refresh_token" => token.instance_variable_get(:@refresh_token),
        "expires_at"    => token.instance_variable_get(:@expires_at)&.to_i ||
                           (Time.now.to_i + (token.instance_variable_get(:@expires_in) || 300)),
        "token_type"    => token.instance_variable_get(:@token_type),
        "scope"         => token.instance_variable_get(:@scope),
        "token_endpoint" => token.instance_variable_get(:@token_endpoint) ||
                            discover_token_endpoint(server_url)
      }
      write(all)
      all[server_url]
    end

    private

    def load
      return {} unless File.exist?(@path)
      JSON.parse(File.read(@path))
    rescue JSON::ParserError
      {}
    end

    def write(data)
      File.write(@path, JSON.pretty_generate(data))
    end

    def refresh(server_url, data)
      refresh_token = data["refresh_token"]
      return nil unless refresh_token

      token_endpoint = data["token_endpoint"]
      return nil unless token_endpoint

      uri      = URI(token_endpoint)
      http     = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      form = URI.encode_www_form(
        grant_type:    "refresh_token",
        refresh_token: refresh_token,
        client_id:     extract_client_id(server_url)
      )

      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = form

      res = http.request(req)
      return nil unless res.is_a?(Net::HTTPSuccess)

      new_data = JSON.parse(res.body)
      all = load
      all[server_url] = data.merge(
        "access_token" => new_data["access_token"],
        "expires_at"   => Time.now.to_i + new_data["expires_in"].to_i,
        "refresh_token" => new_data["refresh_token"] || refresh_token
      )
      write(all)
      new_data["access_token"]
    rescue => e
      warn "Frai: Silent token refresh failed — #{e.message}"
      nil
    end

    def discover_token_endpoint(server_url)
      # Try to discover from OAuth metadata
      uri = URI(server_url)
      meta_url = "#{uri.scheme}://#{uri.host}/.well-known/oauth-authorization-server"
      res = Net::HTTP.get_response(URI(meta_url))
      return nil unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)["token_endpoint"]
    rescue
      nil
    end

    def extract_client_id(server_url)
      # Extract client_id from cached data or default
      all = load
      all.dig(server_url, "client_id") || "mcp-context-forge-prod"
    end

    def ensure_gitignored
      gitignore = File.join(File.dirname(@path), ".gitignore")
      return unless File.exist?(gitignore)
      filename = File.basename(@path)
      content  = File.read(gitignore)
      return if content.include?(filename)
      File.write(gitignore, content.rstrip + "\n#{filename}\n")
    end
  end
end
