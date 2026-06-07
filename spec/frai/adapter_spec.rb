# frozen_string_literal: true

require "spec_helper"

RSpec.describe Frai::Task do
  subject(:task) { described_class.new }

  after { Frai.reset! }

  describe "#adapter" do
    context "without model configured" do
      before { Frai.configure { |c| c.model = nil } }

      it "returns a Null adapter" do
        expect(task.send(:adapter)).to be_a(Frai::Adapters::Null)
      end
    end

    context "with model configured", :aggregate_failures do
      before do
        Frai.configure do |c|
          c.model   = "claude-opus-4-6"
          c.api_key = "test-key"
        end
      end

      if Gem::Specification.find_all_by_name("ruby_llm").any?
        it "returns a RubyLlm adapter" do
          expect(task.send(:adapter)).to be_a(Frai::Adapters::RubyLlm)
        end
      else
        it "raises Frai::Error when ruby_llm is unavailable" do
          expect { task.send(:adapter) }.to raise_error(Frai::Error)
        end
      end
    end
  end
end
