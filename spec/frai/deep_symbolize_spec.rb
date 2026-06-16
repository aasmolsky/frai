# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::DeepSymbolize do
  describe ".call" do
    it "symbolizes hash keys recursively" do
      input = {
        "processed_reviews" => [
          { "review_id" => "r1", "score_breakdown" => [{ "key" => "X", "value" => 1 }] }
        ]
      }

      expect(described_class.call(input)).to eq(
        processed_reviews: [
          { review_id: "r1", score_breakdown: [{ key: "X", value: 1 }] }
        ]
      )
    end

    it "leaves scalars unchanged" do
      expect(described_class.call("text")).to eq("text")
      expect(described_class.call(42)).to eq(42)
      expect(described_class.call(nil)).to be_nil
    end
  end

  describe "Frai.deep_symbolize" do
    it "delegates to DeepSymbolize.call" do
      expect(Frai.deep_symbolize("a" => 1)).to eq(a: 1)
    end
  end
end
