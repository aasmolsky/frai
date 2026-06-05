# Frai

**Frai** is a Ruby framework for building LLM-powered tasks, pipelines, and agents.

Ruby is an expressive language built for developer happiness — but it rarely appears in AI tooling, where Python dominates. Frai brings Rails-style conventions to LLM workflows: clear structure, sensible defaults, and a simple contract that scales from a single prompt to a multi-agent system.

---

## Installation

Install the gem globally:

```bash
gem install frai
```

Or add to your Gemfile (if embedding in an existing project):

```ruby
gem "frai"
```

```bash
bundle install
```

---

## Getting started

```bash
frai new my_project
cd my_project
bundle install
```

Generated structure:

```
my_project/
  tasks/
    base_task.rb
  pipelines/
    base_pipeline.rb
  agents/
    base_agent.rb
  scripts/             # shared scripts
  directives/          # shared prompt templates
  mcp/                 # external MCP server definitions
  config/
    frai.rb            # adapter, model, API key
  .env                 # local secrets — git-ignored
  .env.example         # template to commit
  .gitignore
  spec/
    conventions_spec.rb
```

The generated `Gemfile` already includes `gem "frai"` — run `bundle install` to install dependencies.

**Full first-run flow:**

```bash
frai new my_project
cd my_project
bundle install          # install dependencies
cp .env.example .env    # fill in your secrets
# add mcp/*.rb files if needed
frai setup              # register MCP servers with Claude CLI
frai gt analyze_item    # generate your first task
```

---

## Tasks

A task is the core unit — **one LLM call**. It validates input, runs scripts to gather data, renders a prompt from templates, and sends it to the LLM.

### Minimal

```ruby
class AnalyzeItemTask < BaseTask
end

AnalyzeItemTask.call("some input")
```

### With params and constants

```ruby
class CodeReviewTask < BaseTask
  directive :main do
    params do
      required :task_id, String   # Frai::MissingParam if absent
      optional :lang,    String, default: "en"
    end

    use :check_resources

    use :context do
      run :fetch_diff do
        input   String
        returns diff: String
      end
    end
  end
end
```

`task.rb` is the contract — params, constants, sub-directives, and scripts are declared here.

---

## Directives

Directives are Markdown + ERB prompt templates. `main.md.erb` is always the entry point.

### Variables

Params and constants are available as plain methods:

```erb
You are a senior engineer performing a code review for task <%= task_id %>.
```

### Scripts

```erb
<% run(:fetch_diff).with(:task_id).and_return(:diff) %>
<%= diff %>
```

- `.with(:param)` — pass a value from current context by name
- `.and_return(:key)` — extract `:key` from script JSON output and expose as method

### Sub-directives

```erb
<%= use(:check_resources) %>
<% use(:context).with(:task_id).and_return(:diff) %>
```

### Conditional logic

```erb
<% if score > threshold %>
  <%= use(:high_score).with(:score) %>
<% else %>
  <%= use(:low_score).with(:score) %>
<% end %>
```

### Shared directives

```
directives/
  check_resources.md.erb   # reusable across tasks
```

---

## Scripts

Scripts receive `{ input: value }` as JSON on stdin and write a JSON hash to stdout:

```ruby
# tasks/code_review/scripts/fetch_diff.rb
require 'json'
input = JSON.parse($stdin.read, symbolize_names: true)[:input]
puts JSON.generate({ diff: "diff for #{input}" })
```

```python
# tasks/analyze_item/scripts/fetch.py
import sys, json
data = json.load(sys.stdin)
print(json.dumps({ "result": f"fetched: {data['input']}" }))
```

Scripts in `scripts/` are never autoloaded — they run as subprocesses. Results are memoized per task execution.

---

## Environment variables

Each project has a `.env` file (git-ignored) for local secrets:

```bash
# .env
JIRA_MCP_URL=https://...
GITLAB_URL=https://xdevteam.com
GITLAB_TOKEN=your_token
```

Commit `.env.example` with empty values as a template for teammates. `config/frai.rb` loads `.env` automatically on startup.

---

## External MCP servers

Declare required MCP servers in `mcp/*.rb`. Supports both HTTP and stdio transports:

```ruby
# mcp/jira.rb — HTTP (hosted)
Frai::MCP.define :jira do
  url ENV["JIRA_MCP_URL"]
end

# mcp/gitlab.rb — stdio (local)
Frai::MCP.define :gitlab do
  command "uv"
  args    ["--directory", "~/softswiss/gitlab-mcp", "run", "main.py"]
  env     GITLAB_URL: ENV["GITLAB_URL"], GITLAB_TOKEN: ENV["GITLAB_TOKEN"]
end
```

Register with Claude CLI and disable approval prompts:

```bash
frai setup   # or: frai s
```

Run `frai setup` when:
- After `frai new` — once MCP definitions are added
- After adding a new `mcp/*.rb` file
- After cloning the project on a new machine

Analogous to `bundle install` — run when MCP dependencies change.

---

## Claude CLI integration

Each task gets its own slash command. `frai gt` creates it automatically:

```bash
frai gt code_review
# → creates task files
# → creates .claude/commands/code_review.md
```

Invoke from Claude CLI **inside the project directory**:

```
/code_review task_id(PDB-111)
/code_review task_id(PDB-111) lang(en)
```

Arguments use `name(value)` format — names match params declared in `task.rb`. Also supports `key:value` format:

```
/code_review task_id:PDB-111
```

If the command fails, Claude reports the error and stops — it does not retry or guess parameters.

---

## Pipelines

A pipeline chains tasks sequentially — output of each step becomes input of the next:

```bash
frai gp review_pipeline   # short for: frai generate pipeline
```

```ruby
class ReviewPipeline < BasePipeline
  def call(input)
    diff   = FetchDiffTask.call(input)
    review = CodeReviewTask.call(diff)
    review
  end
end

ReviewPipeline.call("task_id(PDB-111)")
```

---

## Agents

An agent orchestrates tasks dynamically — it can branch, loop, and decide what to call next based on intermediate results:

```bash
frai ga research_agent   # short for: frai generate agent
```

```ruby
class ResearchAgent < BaseAgent
  def call(input)
    data    = FetchDataTask.call(input)
    summary = SummarizeTask.call(data)
    summary
  end
end

ResearchAgent.call("some topic")
```

---

## Configuration

```ruby
# config/frai.rb
Frai.configure do |config|
  config.adapter = :anthropic          # :anthropic, :openai, :ollama, :null
  config.model   = "claude-opus-4-6"
  config.api_key = ENV["ANTHROPIC_API_KEY"]
end
```

The `:null` adapter returns the rendered prompt without making an LLM call — useful for testing.

---

## Removing a task

```bash
frai rt code_review   # short for: frai remove task
```

Removes the task directory and `.claude/commands/code_review.md`.

## Destroying a project

Before deleting the project directory, clean up external artifacts:

```bash
cd my_project
frai destroy
# → removes MCP server registrations
# → lists command files to be removed
cd ..
rm -rf my_project
```

---

## CLI reference

| Command | Description |
|---|---|
| `frai new PROJECT_NAME` | Create a new project (`frai n`) |
| `frai generate task NAME` | Generate a task + Claude CLI command (`frai gt`) |
| `frai generate pipeline NAME` | Generate a pipeline (`frai gp`) |
| `frai generate agent NAME` | Generate an agent (`frai ga`) |
| `frai remove task NAME` | Remove a task and its Claude CLI command (`frai rt`) |
| `frai setup` | Register `mcp/*.rb` servers with Claude CLI, disable approval prompts (`frai s`) |
| `frai destroy` | Clean up MCP servers and commands before deleting the project |
| `frai exec CLASS_NAME [INPUT]` | Execute a task, pipeline, or agent (`frai e`) |
| `frai console` | Interactive Ruby console with project loaded (`frai c`) |

---

## License

MIT
