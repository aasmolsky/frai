# Frai

**Frai** is a Ruby framework for building LLM-powered tasks, pipelines, and agents.

Ruby is an expressive language built for developer happiness — but it rarely appears in AI tooling, where Python dominates. Frai brings Rails-style conventions to LLM workflows: clear structure, sensible defaults, and a simple contract that scales from a single prompt to a multi-agent system.

---

## Installation

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
frai generate task analyze_item
```

Generated structure:

```
my_project/
  tasks/
    base_task.rb
    analyze_item/
      task.rb
      directives/
        main.md.erb    # prompt template — entry point
      scripts/         # executables in any language
  pipelines/
    base_pipeline.rb
  agents/
    base_agent.rb
  scripts/             # shared scripts
  directives/          # shared prompt templates
  config/
    frai.rb            # adapter, model, API key
  spec/
    conventions_spec.rb
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
class SumNumbersTask < BaseTask
  const :high_value_threshold, 10   # available in all directives as high_value_threshold

  directive :main do
    params do
      required :input_numbers, String   # Frai::MissingParam if absent
      optional :lang,          String, default: "en"
    end

    directive :sum do
      script :parse_numbers do
        input   String
        returns parsed_numbers: [Integer]
      end
      script :sum_numbers do
        input   [Integer]
        returns calculated_sum: Integer
      end
    end

    directive :high_value do
      params { required :calculated_sum, Integer }
    end

    directive :low_value do
      params { required :calculated_sum, Integer }
    end
  end
end
```

`task.rb` is the contract — it declares what the task needs, what scripts it runs, and what sub-directives it uses. Types and structure live here; logic lives in the templates.

---

## Directives

Directives are Markdown + ERB prompt templates. `main.md.erb` is always the entry point for the LLM call.

### Variables

Params, constants, and script results are available as plain methods:

```erb
You are an expert analyst.
Analyze: <%= input %>
Respond in: <%= lang %>
```

### Scripts

Run a script and capture its result:

```erb
<% script(:parse_numbers).with(:input_numbers).and_return(:parsed_numbers) %>
<% script(:sum_numbers).with(:parsed_numbers).and_return(:calculated_sum) %>
```

- `.with(:param)` — pass a value from the current context by name
- `.and_return(:key)` — extract `:key` from the script's JSON output and expose it as a method

### Sub-directives

Render a sub-directive and capture its result:

```erb
<% directive(:sum).with(:input_numbers).and_return(:calculated_sum) %>
```

Output a sub-directive's rendered text:

```erb
<%= directive(:high_value).with(:calculated_sum) %>
```

### Conditional logic

Full Ruby is available in templates:

```erb
<% directive(:sum).with(:input_numbers).and_return(:calculated_sum) %>

<% if calculated_sum > high_value_threshold %>
  <%= directive(:high_value).with(:calculated_sum) %>
<% else %>
  <%= directive(:low_value).with(:calculated_sum) %>
<% end %>
```

### Shared directives

Directives reused across tasks go in the top-level `directives/` folder:

```
directives/
  system.md.erb   # available to all tasks as a fallback
```

---

## Scripts

Scripts are executables in any language. They receive `{ input: value }` as JSON on stdin and write a JSON hash to stdout.

```ruby
# tasks/sum_numbers/scripts/parse_numbers.rb
require 'json'
input_str = JSON.parse($stdin.read, symbolize_names: true)[:input]
numbers   = input_str.split(",").map(&:strip).map(&:to_i)
puts JSON.generate({ parsed_numbers: numbers })
```

```python
# tasks/analyze_item/scripts/fetch.py
import sys, json
data = json.load(sys.stdin)
print(json.dumps({ "title": f"Fetched: {data['input']}" }))
```

Scripts in `scripts/` are never autoloaded — they are run as subprocesses by `ScriptRunner`. Script results are memoized per task execution.

---

## Pipelines

A pipeline chains tasks sequentially. Each task's output becomes the next task's input:

```ruby
class CompareObjectsPipeline < BasePipeline
  def call(input)
    data   = FetchDataTask.call(input)
    result = AnalyzeItemTask.call(data)
    result
  end
end

CompareObjectsPipeline.call("your input")
```

---

## Agents

An agent orchestrates tasks dynamically — it can branch, loop, and decide what to call next:

```ruby
class ResearchAgent < BaseAgent
  def call(input)
    data    = FetchDataTask.call(input)
    summary = SummarizeTask.call(data)
    summary
  end
end

ResearchAgent.call("topic to research")
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

The `:null` adapter returns the rendered prompt without making an LLM call — useful for testing and MCP mode.

---

## MCP server mode

Expose all project tasks as tools for Claude CLI, Codex, or Cursor. Running `frai generate task` automatically registers the skill:

```bash
frai generate task sum_numbers
# → creates task files
# → detects installed AI clients (Claude CLI, Codex, Cursor)
# → registers MCP server for the project
# → creates skill ~/.claude/skills/sum_numbers/ and/or ~/.codex/skills/sum_numbers/
# → disables approval prompts
```

Each task gets its own skill. Invoke it by task name in Claude CLI:

```
/sum_numbers input_numbers(1,2,3)
```

Where `input_numbers` is the parameter name declared in `task.rb`. Required params missing → error.

The skill automatically includes `_skill: "sum_numbers"` in every tool call — the MCP server rejects requests without it. Tools are only accessible through their skill.

---

## Removing a task and its skill

`frai generate task` creates files in several places. To fully undo, run from inside the project:

```bash
frai remove task analyze_item
```

This removes the task directory, MCP server registration, skill files, and all config entries across Claude CLI, Codex, and Cursor automatically.

If you prefer to do it manually:

**1. Delete task files:**
```bash
rm -rf tasks/<name>
```

**2. Remove MCP server:**
```bash
claude mcp remove <project_name>     # Claude CLI
codex mcp remove <project_name>      # Codex CLI (if installed)
# Cursor: edit ~/.cursor/mcp.json and remove the entry
```

**3. Remove skill:**
```bash
rm -rf ~/.claude/skills/<name>       # Claude CLI skill
rm -rf ~/.codex/skills/<name>        # Codex skill (if installed)
rm .cursor/rules/<name>.mdc          # Cursor rules (if exists)
```

**4. Remove entries from global config files:**
```bash
# ~/.claude/CLAUDE.md — delete the <!-- frai:<name> --> block
# ~/.codex/config.toml — delete the [mcp_servers.<project_name>] block
# AGENTS.md — delete the <!-- frai:<name> --> block
```

**5. Remove approval settings:**
```bash
# .claude/settings.local.json — remove "mcp__<project_name>__*" from permissions.allow
```

---

## CLI reference

| Command | Description |
|---|---|
| `frai new PROJECT_NAME` | Create a new project (`frai n`) |
| `frai generate task NAME` | Generate a task + register skill (`frai g task`, `frai gt`) |
| `frai generate pipeline NAME` | Generate a pipeline (`frai g pipeline`, `frai gp`) |
| `frai generate agent NAME` | Generate an agent (`frai g agent`, `frai ga`) |
| `frai generate skill NAME` | Register project as a skill (`frai g skill`) |
| `frai remove task NAME` | Remove a task and clean up skill, MCP, and config entries (`frai r task`, `frai rt`) |
| `frai exec CLASS_NAME [INPUT]` | Execute a task, pipeline, or agent (`frai e`) |
| `frai console` | Interactive Ruby console with project loaded (`frai c`) |
| `frai serve --dir PATH` | Start MCP server (`frai s`) |

---

## License

MIT
