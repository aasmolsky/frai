# frozen_string_literal: true

require "json"
require "ruby_llm/mcp"

module Frai
  module MCP
    # File-backed OAuth storage for ruby_llm-mcp.
    # Implements the same interface as RubyLLM::MCP::Auth::MemoryStorage so
    # token refresh, client registration, and browser OAuth flows are handled by the gem.
    class OAuthStorage
      CACHE_FILE = ".frai_oauth_cache.json"

      SECTIONS = {
        tokens:            RubyLLM::MCP::Auth::Token,
        client_infos:      RubyLLM::MCP::Auth::ClientInfo,
        server_metadata:   RubyLLM::MCP::Auth::ServerMetadata,
        pkce_data:         RubyLLM::MCP::Auth::PKCE,
        state_data:        nil,
        resource_metadata: RubyLLM::MCP::Auth::ResourceMetadata
      }.freeze

      def initialize(project_root)
        @path     = File.join(project_root, CACHE_FILE)
        @mutex    = Mutex.new
        @migrated = false
        @data     = load
        persist if @migrated
        ensure_gitignored
      end

      def get_token(server_url)            = deserialize(:tokens, server_url)
      def set_token(server_url, token)     = store(:tokens, server_url, token&.to_h)
      def delete_token(server_url)         = delete(:tokens, server_url)

      def get_client_info(server_url)      = deserialize(:client_infos, server_url)
      def set_client_info(server_url, info) = store(:client_infos, server_url, info&.to_h)

      def get_server_metadata(server_url)  = deserialize(:server_metadata, server_url)
      def set_server_metadata(server_url, metadata) = store(:server_metadata, server_url, metadata&.to_h)

      def get_pkce(server_url)             = deserialize(:pkce_data, server_url)
      def set_pkce(server_url, pkce)       = store(:pkce_data, server_url, pkce&.to_h)
      def delete_pkce(server_url)          = delete(:pkce_data, server_url)

      def get_state(server_url)            = read_section(:state_data, server_url)
      def set_state(server_url, state)     = store(:state_data, server_url, state)
      def delete_state(server_url)         = delete(:state_data, server_url)

      def get_resource_metadata(server_url) = deserialize(:resource_metadata, server_url)
      def set_resource_metadata(server_url, metadata) = store(:resource_metadata, server_url, metadata&.to_h)
      def delete_resource_metadata(server_url) = delete(:resource_metadata, server_url)

      private

      def section(name)
        @data[name.to_s] ||= {}
      end

      def store(section_name, server_url, value)
        @mutex.synchronize do
          key = normalize(server_url)
          if value.nil?
            section(section_name).delete(key)
          else
            section(section_name)[key] = value
          end
          persist
        end
      end

      def delete(section_name, server_url)
        @mutex.synchronize do
          section(section_name).delete(normalize(server_url))
          persist
        end
      end

      def deserialize(section_name, server_url)
        raw = read_section(section_name, server_url)
        return nil unless raw

        klass = SECTIONS[section_name]
        return raw unless klass

        klass.from_h(raw.transform_keys(&:to_sym))
      end

      def read_section(section_name, server_url)
        @mutex.synchronize { section(section_name)[normalize(server_url)] }
      end

      def normalize(server_url)
        RubyLLM::MCP::Auth::OAuthProvider.normalize_url(server_url)
      end

      def default_data
        SECTIONS.keys.to_h { |k| [k.to_s, {}] }
      end

      def load
        return default_data unless File.exist?(@path)

        raw = JSON.parse(File.read(@path))
        migrate_legacy_format(raw)
      rescue JSON::ParserError
        default_data
      end

      # Older Frai caches stored token hashes directly keyed by server URL.
      def migrate_legacy_format(raw)
        if raw.key?("tokens") || raw.empty? || raw.keys.none? { |k| k.to_s.start_with?("http") }
          @migrated = false
          return raw
        end

        @migrated = true
        tokens = raw.transform_values { |entry| migrate_legacy_token_entry(entry) }
        default_data.merge("tokens" => tokens)
      end

      def migrate_legacy_token_entry(entry)
        return entry unless entry.is_a?(Hash)

        migrated = entry.dup
        expires_at = migrated["expires_at"] || migrated[:expires_at]
        if expires_at.is_a?(Integer)
          migrated["expires_at"] = Time.at(expires_at).iso8601
        end
        migrated
      end

      def persist
        File.write(@path, JSON.pretty_generate(@data))
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
end
