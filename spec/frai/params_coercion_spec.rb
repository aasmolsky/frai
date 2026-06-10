# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "CLI arguments processing in Task" do
  after { Frai.reset! }

  let(:task_class) do
    Class.new(Frai::Task) do
      def self.name; "CliTask"; end
      def self.task_name; "cli_task"; end

      schema do
        llm false
        param :place_data, type: Hash, required: true do
          required(:id).filled(:string)
        end
        param :tags, type: Array, required: false, default: []
        param :limit, type: Integer, required: true
        param :strict, type: Object, required: false, default: false

        output Hash
      end

      def call(input)
        super
      end
    end
  end

  before do
    Frai.configure do |config|
      config.project_root = Dir.pwd
      config.env          = :test
    end
  end

  describe "#coerce_string_params" do
    let(:instance) { task_class.new }
    let(:declaration) { task_class._directive_declaration }

    it "coerces plain JSON strings to Hash" do
      input = { "place_data" => '{"id":"abc","score":42}' }
      # Ensure symbol keys as typically provided internally/by cli mapper
      input.transform_keys!(&:to_sym)

      result = instance.send(:coerce_string_params, declaration.params_declaration, input)
      expect(result[:place_data]).to eq({ "id" => "abc", "score" => 42 })
    end

    it "coerces Ruby Hash strings to Hash via eval" do
      # Note: eval is intentionally used for CLI single-quote convenience e.g.: '{id: 123}'
      input = { place_data: "{ 'id' => 123 }" }
      result = instance.send(:coerce_string_params, declaration.params_declaration, input)
      expect(result[:place_data]).to eq({ "id" => 123 })
    end

    it "leaves non-string params intact" do
      input = { place_data: { id: "real_hash" } }
      result = instance.send(:coerce_string_params, declaration.params_declaration, input)
      expect(result[:place_data]).to eq({ id: "real_hash" })
    end

    it "coerces JSON arrays" do
      input = { tags: '["urgent", "review"]' }
      result = instance.send(:coerce_string_params, declaration.params_declaration, input)
      expect(result[:tags]).to eq(["urgent", "review"])
    end
  end

  describe "validation error message format" do
    it "shows exact type mismatches without exploding" do
      expect {
        task_class.call(place_data: { id: "1" }, limit: "not an integer")
      }.to raise_error(Frai::InvalidParam, /:limit expected Integer, got String/)
    end
  end
end
