# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::JsonResponse do
  describe ".clean" do
    it "strips markdown fences" do
      raw = <<~TEXT
        ```json
        {"ok": true}
        ```
      TEXT

      expect(described_class.clean(raw)).to eq('{"ok": true}')
    end
  end

  describe ".normalize" do
    it "accepts a Hash from ruby_llm with_schema" do
      result = described_class.normalize({ "place_id" => "abc", "count" => 2 })

      expect(result).to eq(place_id: "abc", count: 2)
    end

    it "parses a JSON string in strict mode" do
      result = described_class.normalize('{"place_id": "abc", "count": 2}', strict: true)

      expect(result).to eq(place_id: "abc", count: 2)
    end

    it "repairs trailing commas only in lenient mode" do
      expect do
        described_class.normalize('{"items": [1,2,],}', strict: true)
      end.to raise_error(Frai::JsonParseError)

      result = described_class.normalize('{"items": [1,2,],}', strict: false)
      expect(result).to eq(items: [1, 2])
    end

    it "raises JsonParseError for non-JSON text", :aggregate_failures do
      expect { described_class.normalize("not json at all") }
        .to raise_error(Frai::JsonParseError, /invalid JSON/)

      error = nil
      begin
        described_class.normalize("not json at all", attempt: 2, task_class: String)
      rescue Frai::JsonParseError => e
        error = e
      end

      expect(error.attempt).to eq(2)
      expect(error.task_class).to eq(String)
      expect(error.raw_preview).to include("not json")
    end

    it "raises JsonParseError when root is not an object" do
      expect { described_class.normalize("[1, 2, 3]") }
        .to raise_error(Frai::JsonParseError, /expected JSON object/)
    end

    it "runs the validator block", :aggregate_failures do
      validator = lambda do |data, context|
        raise Frai::ValidationError, "missing reviews" if data[:processed_reviews].nil?
        raise Frai::ValidationError, "count mismatch" if data[:processed_reviews].size != context[:reviews].size
      end

      result = described_class.normalize(
        { "processed_reviews" => [{ "id" => "1" }] },
        validate: validator,
        context:  { reviews: [{ id: "1" }] }
      )

      expect(result).to eq(processed_reviews: [{ id: "1" }])
    end

    it "wraps unexpected validator exceptions as ValidationError" do
      validator = ->(_data, _context) { raise ArgumentError, "boom" }

      expect do
        described_class.normalize({ "ok" => true }, validate: validator)
      end.to raise_error(Frai::ValidationError, /validator raised ArgumentError/)
    end

    it "runs a validator method on the receiver when given" do
      receiver = Class.new do
        def validate_response!(data, context)
          raise Frai::ValidationError, "count mismatch" if data[:count] != context[:expected]
        end
      end.new

      result = described_class.normalize(
        { "count" => 2 },
        validate:           :validate_response!,
        validator_receiver: receiver,
        context:            { expected: 2 }
      )

      expect(result).to eq(count: 2)
    end
  end
end
