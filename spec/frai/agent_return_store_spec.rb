# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::AgentReturnStore do
  after { Thread.current[described_class::KEY] = nil }

  it "captures and returns a value within with_store" do
    result = described_class.with_store do
      described_class.capture({ report: 1 })
      described_class.value
    end

    expect(result).to eq(report: 1)
    expect(described_class.value).to be_nil
  end

  it "restores the previous value after with_store" do
    described_class.capture(:outer)

    described_class.with_store do
      described_class.capture(:inner)
      expect(described_class.value).to eq(:inner)
    end

    expect(described_class.value).to eq(:outer)
  end
end
