module Frai
  # Base class for all Frai pipelines.
  #
  # A pipeline chains multiple tasks sequentially. The output of each
  # step becomes the input for the next. Pipelines share the same
  # external contract as tasks: {.call}.
  #
  # @example
  #   class CompareObjectsPipeline < Frai::Pipeline
  #     step FetchDataTask
  #     step AnalyzeItemTask
  #     step FormatResultTask
  #   end
  #
  #   CompareObjectsPipeline.call("object description")
  class Pipeline
    # Instantiates and calls the pipeline.
    #
    # @param input [Object, nil] input passed to the first step
    # @return [Object] result of the last step
    def self.call(input = nil)
      new.call(input)
    end

    # Executes the pipeline steps in order.
    # Override in subclasses to customize behavior.
    #
    # @param input [Object, nil] input passed to the first step
    # @return [Object] result of the last step
    def call(input = nil)
      raise NotImplementedError, "#{self.class}#call is not implemented"
    end
  end
end
