require "frai"

RSpec.describe "Project conventions" do
  describe "tasks" do
    Dir[File.join(__dir__, "..", "tasks", "**", "*.rb")].each do |file|
      require file
      class_name = File.basename(file, ".rb").split("_").map(&:capitalize).join
      next if class_name == "BaseTask"

      describe class_name do
        let(:klass) { Object.const_get(class_name) }

        it "inherits from BaseTask" do
          expect(klass.ancestors).to include(BaseTask)
        end

        it "responds to .call" do
          expect(klass).to respond_to(:call)
        end
      end
    end
  end

  describe "pipelines" do
    Dir[File.join(__dir__, "..", "pipelines", "**", "*.rb")].each do |file|
      require file
      class_name = File.basename(file, ".rb").split("_").map(&:capitalize).join
      next if class_name == "BasePipeline"

      describe class_name do
        let(:klass) { Object.const_get(class_name) }

        it "inherits from BasePipeline" do
          expect(klass.ancestors).to include(BasePipeline)
        end

        it "responds to .call" do
          expect(klass).to respond_to(:call)
        end
      end
    end
  end
end
