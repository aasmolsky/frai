# frozen_string_literal: true

# Force test env before frai loads — never inherit production from the shell or .env.
ENV["FRAI_ENV"] = "test"

require "frai"

RSpec.configure do |config|
  config.before { ENV["FRAI_ENV"] = "test" }
  config.after { Frai.reset! }
end
