# Frai

**Frai** is a Ruby framework for building LLM-powered tasks, pipelines and agents.

Ruby is an expressive language built for developer happiness — but it rarely appears in AI tooling, where Python dominates. Frai is an attempt to bring Rails-style conventions to LLM workflows: clear structure, sensible defaults, and a simple contract that scales from a single prompt to a multi-agent system.

The heavy lifting — LLM calls, subprocess scripts, I/O — happens outside Ruby's runtime. So you get the elegance of Ruby DSL with none of the performance concerns.

---

## Installation

Add to your Gemfile:

```ruby
gem "frai"
```

Then install:

```bash
bundle install
```

You'll also need a gem for your LLM provider:

```ruby
gem "anthropic"    # for Claude
gem "ruby-openai"  # for OpenAI
gem "ollama-ai"    # for Ollama (local models)
```

---

## Getting started

Create a new project:

```bash
frai new my_project
cd my_project
bundle install
```

This generates the following structure:

```
my_project/
  tasks/               # single LLM calls — the main building block
    base_task.rb       # parent class for all your tasks
  pipelines/           # sequential chains of tasks
    base_pipeline.rb
  agents/              # orchestrators that decide what to call and when
    base_agent.rb
  tools/               # Ruby wrappers around scripts
  scripts/             # shared scripts in any language (Python, JS, bash...)
  mcp/                 # MCP server configurations
  directives/          # shared prompt templates (reused across tasks)
    base.md.erb
  config/
    frai.rb            # LLM adapter, model, API key
  spec/
    conventions_spec.rb
```

---

## Tasks

A task is the core unit in Frai — it represents a single LLM call.

Generate a task:

```bash
frai generate task analyze_item
```

This creates:

```
tasks/
  analyze_item/
    task.rb              # the task class
    directives/
      main.md.erb        # entry point prompt template
    scripts/             # optional scripts for this task
```

The generated `task.rb`:

```ruby
class AnalyzeItemTask < BaseTask
  directive :main
end
```

`directive :main` tells Frai to use `directives/main.md.erb` as the entry point. That's the minimum — no other configuration needed.

To run it:

```bash
frai exec AnalyzeItemTask "your input here"
```

Or from Ruby:

```ruby
AnalyzeItemTask.call("your input here")
```

---

## Directives

A directive is a prompt template written in Markdown with ERB. `main.md.erb` is always the entry point — Frai renders it first.

```markdown
<%# tasks/analyze_item/directives/main.md.erb %>

You are an expert analyst.

Analyze the following:
<%= input %>
```

`input` contains whatever was passed to `.call(input)`.

### Declaring dependencies

A directive can depend on other directives and scripts. Declare them in `task.rb` — this is the task's full contract:

```ruby
class AnalyzeItemTask < BaseTask
  directive :main do
    uses :system       # renders tasks/analyze_item/directives/system.md.erb
    uses :context      # renders tasks/analyze_item/directives/context.md.erb
    runs :fetch_data   # runs tasks/analyze_item/scripts/fetch_data.*
  end
end
```

Script results are memoized — each script runs only once per task execution. Results are available as variables inside the directive:

```markdown
<%# fetch_data ran once, result cached — available as fetch_data[:key] %>
Item title: <%= fetch_data[:title] %>
Item price: <%= fetch_data[:price] %>
```

Anything not declared in the block cannot be used in directive templates. Violations raise a descriptive error before any LLM call is made.

### Input params

`params` is optional — omit it to accept any input without validation. Declare it inside the `directive` block when you want strict input checking:

```ruby
class AnalyzeItemTask < BaseTask
  directive :main do
    params do
      required :name,     String   # Frai::MissingParam if absent
      required :category, String   # Frai::InvalidParam if wrong type
      optional :lang,     String, default: "en"
    end
    uses :system
    runs :fetch_data
  end
end
```

Validation runs as the first step of `.call` — before any directive is rendered, any script is executed, or any LLM call is made. If validation fails, Frai raises immediately with a descriptive error.

`required` checks that the key exists and matches the declared type. `optional` applies the default value if the key is absent, and checks the type if the key is present.

```ruby
AnalyzeItemTask.call(name: "item", category: "things")
# lang defaults to "en"

AnalyzeItemTask.call(name: "item")
# => Frai::MissingParam: required param :category is missing in AnalyzeItemTask

AnalyzeItemTask.call(name: 123, category: "things")
# => Frai::InvalidParam: :name expected String, got Integer in AnalyzeItemTask

AnalyzeItemTask.call("not a hash")
# => Frai::InvalidParam: AnalyzeItemTask declares params — input must be a Hash
```

Inside directives, params are available as individual variables:

```markdown
Analyze this <%= category %>: <%= name %>
Respond in <%= lang %>
```

### Reusable schemes

For complex tasks with many dependencies, extract named blocks:

```ruby
class AnalyzeItemTask < BaseTask
  directive :main do
    uses :system
    uses :context do
      include_scheme :data_gathering
    end
  end

  scheme :data_gathering do
    runs :get_data
    runs :fetch_data
  end
end
```

### Custom logic

Override `call` to add logic before or after the LLM call:

```ruby
class AnalyzeItemTask < BaseTask
  directive :main

  def call(input)
    result = super   # renders prompt, calls LLM, returns response
    # post-process result here
    result
  end
end
```

### Shared directives

Directives reused across multiple tasks go in the top-level `directives/` folder. Frai looks there as a fallback if a directive is not found inside the task:

```
directives/
  base.md.erb        # available to all tasks
```

---

## Pipelines

A pipeline chains tasks sequentially. The output of each step becomes the input for the next.

Generate a pipeline:

```bash
frai generate pipeline compare_objects
```

```ruby
class CompareObjectsPipeline < BasePipeline
  step FetchDataTask
  step AnalyzeItemTask
  step FormatResultTask
end

CompareObjectsPipeline.call("your input")
```

---

## Agents

An agent orchestrates tasks and tools dynamically. Unlike pipelines, agents are not sequential — they decide what to call based on LLM responses and can loop until the goal is reached.

Generate an agent:

```bash
frai generate agent object_comparison
```

```ruby
class ObjectComparisonAgent < BaseAgent
  tool FetchDataTask
  tool AnalyzeItemTask
end

ObjectComparisonAgent.call("compare object_a, object_b, object_c")
```

---

## Scripts

Scripts are executables in any language — Python, JavaScript, bash, etc. They live inside a task's `scripts/` folder (or in the top-level `scripts/` for shared utilities).

The contract is simple: a script reads JSON from stdin and writes JSON to stdout.

```python
# tasks/analyze_item/scripts/fetch.py
import sys, json

input = json.load(sys.stdin)
result = {"data": f"fetched: {input['query']}"}
print(json.dumps(result))
```

This keeps scripts independently testable — use pytest, jest, or any tool native to that language.

---

## MCP servers

MCP (Model Context Protocol) is a standard for connecting external tools to LLMs. Frai gives each project full control over which MCP servers are available — and enforces isolation at the task level.

Generate an MCP server definition:

```bash
frai generate mcp browser
```

This creates `mcp/browser.rb`:

```ruby
Frai::MCP.define :browser do
  command "npx"
  args    ["-y", "@modelcontextprotocol/server-puppeteer"]
end
```

To use it in a task, declare it explicitly:

```ruby
class FetchDataTask < BaseTask
  directive :main do
    mcp :browser
  end
end
```

**Isolation is enforced programmatically.** If a task tries to use an MCP server that is not declared in its directive block, Frai raises an error before any LLM call is made:

```
Frai::MissingMCP: declared 'mcp :browser' in FetchDataTask
but mcp/browser.rb not found.
Generate it with: frai generate mcp browser
```

A task that does not declare `mcp :browser` cannot access the browser server — even if it is defined in the project. This prevents accidental access to tools that were not intentionally included.

---

## Configuration

Configure your LLM adapter in `config/frai.rb`:

```ruby
Frai.configure do |config|
  config.adapter = :anthropic          # :anthropic, :openai, :ollama
  config.model   = "claude-opus-4-6"
  config.api_key = ENV["ANTHROPIC_API_KEY"]
end
```

Each adapter requires the corresponding gem in your Gemfile. If the gem is missing, Frai raises a clear error telling you what to add.

---

## CLI reference

| Command | Description |
|---|---|
| `frai new PROJECT_NAME` | Create a new Frai project |
| `frai generate task NAME` | Generate a task |
| `frai generate pipeline NAME` | Generate a pipeline |
| `frai generate agent NAME` | Generate an agent |
| `frai generate mcp NAME` | Generate an MCP server definition |
| `frai exec CLASS_NAME [INPUT]` | Execute a task, pipeline or agent |
| `frai console` | Open an interactive Ruby console with the project loaded |

---

## License

MIT
