# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::Task do
  subject(:task) { described_class.new }

  after { Frai.reset! }

  describe "#adapter" do
    context "without adapter configured" do
      before { Frai.configure { |c| c.adapter = nil } }

      it "raises AdapterNotConfigured" do
        expect { task.send(:adapter) }.to raise_error(Frai::AdapterNotConfigured)
      end
    end

    context "with null adapter configured", :aggregate_failures do
      before { Frai.configure { |c| c.adapter = :null } }

      it "returns a Null adapter without raising" do
        expect { task.send(:adapter) }.not_to raise_error
        expect(task.send(:adapter)).to be_a(Frai::Adapters::Null)
      end
    end
  end
end
