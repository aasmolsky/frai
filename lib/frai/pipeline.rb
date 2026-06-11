# frozen_string_literal: true

module Frai
  # Base class for all Frai pipelines.
  #
  # A pipeline chains multiple tasks sequentially. The output of each
  # step becomes the input for the next.
  #
  # @example
  #   class CompareObjectsPipeline < Frai::Pipeline
  #     def call(input)
  #       result = FetchData::Task.call(input)
  #       AnalyzeItem::Task.call(result)
  #     end
  #   end
  #
  #   CompareObjectsPipeline.call("object description")
  class Pipeline
    def self.call(input = nil)
      new.call(input)
    end

    def call(input = nil)
      raise NotImplementedError, "#{self.class}#call is not implemented"
    end
  end
end
