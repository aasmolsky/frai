# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "fileutils"

class CodeReviewTask < Frai::Task; end
class SumNumbersTask < Frai::Task; end

RSpec.describe "Frai YAML task loading" do
  after { Frai.reset! }

  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tasks", "code_review"))
      FileUtils.mkdir_p(File.join(root, "tasks", "sum_numbers"))

      File.write(
        File.join(root, "tasks", "code_review", "task.yml"),
        <<~YAML
          name: code_review

          mcp:
            - jira
            - gitlab

          constants:
            high_value_threshold: 10

          directives:
            main:
              params:
                task_id:
                  required: true
                  type: String

              use:
                code_style_guides:
                  use:
                    naming_rules:
                    formatting_rules:

              run:
                analyze_diff:
                  input:
                    type: String
                  returns:
                    diff_value:
                      type: String
        YAML
      )

      File.write(
        File.join(root, "tasks", "sum_numbers", "task.yml"),
        <<~YAML
          name: sum_numbers

          directives:
            main:
              params:
                input_numbers:
                  required: true
                  type: String
        YAML
      )

      Frai.configure do |config|
        config.project_root = root
        config.env          = :test
      end

      example.run
    end
  end

  it "hydrates one task from its own YAML and keeps another task isolated" do
    code_review = CodeReviewTask._directive_declaration
    sum_numbers = SumNumbersTask._directive_declaration
    code_review_params = code_review&.params_declaration
    sum_numbers_params = sum_numbers&.params_declaration
    code_review_sub_directives = code_review&.sub_directives
    sum_numbers_sub_directives = sum_numbers&.sub_directives
    code_review_script_declarations = code_review&.script_declarations
    sum_numbers_script_declarations = sum_numbers&.script_declarations

    expect(CodeReviewTask._mcps).to eq([:jira, :gitlab])
    expect(CodeReviewTask._constants).to eq(high_value_threshold: 10)
    expect(code_review_params).not_to be_nil
    expect(code_review_params&.required_params).to eq(task_id: String)
    expect(code_review_sub_directives).not_to be_nil
    expect(code_review_sub_directives&.keys).to eq([:code_style_guides])
    expect(code_review_sub_directives&.[](:code_style_guides)&.sub_directives&.keys).to eq([:naming_rules, :formatting_rules])
    expect(code_review_script_declarations).not_to be_nil
    expect(code_review_script_declarations&.keys).to eq([:analyze_diff])

    expect(SumNumbersTask._mcps).to eq([])
    expect(SumNumbersTask._constants).to eq({})
    expect(sum_numbers_params).not_to be_nil
    expect(sum_numbers_params&.required_params).to eq(input_numbers: String)
    expect(sum_numbers_sub_directives).not_to be_nil
    expect(sum_numbers_sub_directives).to be_empty
    expect(sum_numbers_script_declarations).not_to be_nil
    expect(sum_numbers_script_declarations).to be_empty
  end
end




