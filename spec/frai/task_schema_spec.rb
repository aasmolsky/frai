# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Frai schema task loading" do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "code_review"))
      FileUtils.mkdir_p(File.join(root, "tasks", "sum_numbers"))

      File.write(
        File.join(root, "tasks", "code_review", "task.rb"),
        <<~RUBY
          module CodeReview
            class Task < BaseTask
              schema do
                mcp :jira
                mcp :gitlab

                const :high_value_threshold, 10

                param :task_id, type: String, required: true

                use :code_style_guides do
                  use :naming_rules
                  use :formatting_rules
                end

                run :analyze_diff do
                  input   String
                  returns do
                    diff_value String
                  end
                end
              end
            end
          end
        RUBY
      )

      File.write(
        File.join(root, "tasks", "sum_numbers", "task.rb"),
        <<~RUBY
          module SumNumbers
            class Task < BaseTask
              schema do
                param :input_numbers, type: String, required: true

                run :summarize do
                  input   [Integer]
                  returns total: Integer
                end
              end
            end
          end
        RUBY
      )

      load File.join(root, "tasks", "code_review", "task.rb")
      load File.join(root, "tasks", "sum_numbers", "task.rb")

      Frai.configure do |config|
        config.project_root = root
        config.env          = :test
      end

      example.run
    end
  end

  it "hydrates one task from its own Ruby schema and keeps another task isolated" do
    code_review = CodeReview::Task._directive_declaration
    sum_numbers = SumNumbers::Task._directive_declaration
    code_review_params = code_review&.params_declaration
    sum_numbers_params = sum_numbers&.params_declaration
    code_review_sub_directives = code_review&.sub_directives
    sum_numbers_sub_directives = sum_numbers&.sub_directives
    code_review_script_declarations = code_review&.script_declarations
    sum_numbers_script_declarations = sum_numbers&.script_declarations

    expect(CodeReview::Task._mcps).to eq([:jira, :gitlab])
    expect(CodeReview::Task._constants).to eq(high_value_threshold: 10)
    expect(code_review_params).not_to be_nil
    expect(code_review_params&.required_params).to eq(task_id: String)
    expect(code_review_sub_directives).not_to be_nil
    expect(code_review_sub_directives&.keys).to eq([:code_style_guides])
    expect(code_review_sub_directives&.[](:code_style_guides)&.sub_directives&.keys).to eq([:naming_rules, :formatting_rules])
    expect(code_review_script_declarations).not_to be_nil
    expect(code_review_script_declarations&.keys).to eq([:analyze_diff])
    expect(code_review_script_declarations&.[](:analyze_diff)&.input_type).to eq(String)
    expect(code_review_script_declarations&.[](:analyze_diff)&.returns_schema).to eq(diff_value: String)

    expect(SumNumbers::Task._mcps).to eq([])
    expect(SumNumbers::Task._constants).to eq({})
    expect(sum_numbers_params).not_to be_nil
    expect(sum_numbers_params&.required_params).to eq(input_numbers: String)
    expect(sum_numbers_sub_directives).not_to be_nil
    expect(sum_numbers_sub_directives).to be_empty
    expect(sum_numbers_script_declarations).not_to be_nil
    expect(sum_numbers_script_declarations&.keys).to eq([:summarize])
    expect(sum_numbers_script_declarations&.[](:summarize)&.input_type).to eq([Integer])
    expect(sum_numbers_script_declarations&.[](:summarize)&.returns_schema).to eq(total: Integer)
  end
end

