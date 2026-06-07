# frozen_string_literal: true

module Frai
  # Base class for application entrypoints.
  #
  # An application is the stable public interface of a Frai project.
  # External callers (Rails, scripts, other services) always call Application.call(input).
  # The internal implementation — tasks, pipelines, agents — can change freely.
  #
  # @example
  #   class Application < BaseApplication
  #     def call(reviews:, language: "english")
  #       data     = FetchDataTask.call(reviews)
  #       response = AnalyzeTask.call(language: language, data: data)
  #       response
  #     end
  #   end
  #
  #   Application.call(reviews: [...], language: "english")
  class Application
    class << self
      def call(input = nil, **kwargs)
        if kwargs.any?
          new.call(**kwargs)
        else
          new.call(input)
        end
      end
    end

    def call(*)
      raise NotImplementedError, "#{self.class}#call is not implemented"
    end
  end
end

