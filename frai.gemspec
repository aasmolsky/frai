require_relative "lib/frai/version"

Gem::Specification.new do |spec|
  spec.name          = "frai"
  spec.version       = Frai::VERSION
  spec.authors       = ["Alex Smolski"]
  spec.email         = ["alexander.smolsky@gmail.com"]

  spec.summary       = "Ruby LLM framework for tasks, pipelines and agents"
  spec.description   = "Rails-inspired framework for building LLM tasks, pipelines and agents"
  spec.homepage      = "https://github.com/aasmolsky/frai"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files         = Dir["lib/**/*", "bin/*", "LICENSE", "README.md"]
  spec.bindir        = "bin"
  spec.executables   = ["frai"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "irb"

  spec.add_development_dependency "yard",  "~> 0.9"
  spec.add_development_dependency "rspec", "~> 3.13"
end
