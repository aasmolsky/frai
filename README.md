# Frai

**Frai** is a Ruby framework for building LLM-powered tasks, pipelines, and agents.

Ruby is an expressive language built for developer happiness — but it rarely appears in AI tooling, where Python dominates. Frai brings Rails-style conventions to LLM workflows: clear structure, sensible defaults, and a simple contract that scales from a single prompt to a multi-agent system.

Requires Ruby >= 3.3.0.

---

## Installation

Install the gem globally:

```bash
gem install frai
```

Or add to your Gemfile:

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
cp .env.example .env    # fill in your secrets
frai setup              # register MCP servers with Claude CLI
frai gt analyze_item    # generate your first task
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
    frai.rb            # model, API key, autoload
  .env                 # local secrets — git-ignored
  .env.example         # template to commit
  .gitignore
  spec/
    conventions_spec.rb
```

---

## Environments

Frai supports three environments controlled by `FRAI_ENV` in `.env`:

| `FRAI_ENV` | MCPs | LLM | Returns |
|------------|------|-----|---------|
| `development` | skipped | skipped | rendered prompt |
| `test` | skipped | skipped | rendered prompt |
| `production` | connected | called | LLM response |

Default is `production`. In `development` and `test`, all MCP servers are skipped and the null adapter is used regardless of `LLM_MODEL` — you see the rendered prompt without any API calls.

Override inline for a single run:
```bash
FRAI_ENV=production frai exec AnalyzeItemTask "query(test)"
FRAI_ENV=development frai exec AnalyzeItemTask "query(test)"
```

---

## Two modes of operation

**CLI mode** (`LLM_MODEL` not set in `.env`):
- `frai exec` renders the prompt and returns it as text
- Claude CLI reads it and acts as the LLM
- No API key required

**API mode** (`LLM_MODEL` is set):
- `frai exec` renders the prompt, sends it to the LLM via RubyLLM, returns the response
- Works for cron jobs, pipelines, automation — no Claude CLI needed

Switch by setting `LLM_MODEL` in `.env`:

```bash
# API mode
LLM_MODEL=claude-opus-4-6
LLM_API_KEY=your_api_key
```

---

## Tasks

A task is the core unit — **one LLM call**. It validates input, runs scripts, renders a prompt, and optionally calls an LLM.

### Minimal

```ruby
class AnalyzeItemTask < BaseTask
end

AnalyzeItemTask.call("some input")
```

### With params, constants, MCP, sub-directives and scripts

```ruby
class AnalyzeItemTask < BaseTask
  mcp :database   # declared MCP dependencies
  mcp :search

  const :max_issues, 10   # available in all directives

  directive :main do
    params do
      required :query, String
      optional :lang,  String, default: "en"
    end

    use :check_resources   # sub-directive

    use :context do
      run :fetch_diff do
        input   String
        returns diff: String
      end
    end
  end
end
```

`task.yml` is the **contract** — params, constants, MCPs, sub-directives, and scripts are all declared here. The Ruby `task.rb` file becomes a thin entrypoint.

#### YAML equivalent

The same structure can be described declaratively like this:

```yaml
name: code_review

mcp:
  - jira
  - gitlab

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
        params:
          input_var:
            required: true
            type: Hash
        returns:
          diff_value:
            type: String
```

This keeps `use` and `run` inside the directive that owns them, and lets nested directives appear directly under their own name.

**MCP validation rules:**
- Task declares `mcp :name` but `mcp/name.rb` is missing → error at startup
- `mcp/name.rb` exists but no task declares it → error at startup
- MCP not registered with Claude CLI (CLI mode) → error before LLM call
- MCP not accessible (API mode) → error before LLM call

---

## Directives

Directives are Markdown + ERB prompt templates. `main.md.erb` is always the entry point.

### Variables

Params, constants, and script results are available as plain methods:

```erb
You are an expert analyst.
Analyze task <%= task_id %> in <%= lang %>.
```

### Scripts

```erb
<% run(:fetch_diff).with(:task_id).and_return(:diff) %>
<%= diff %>
```

- `.with(:param)` — pass a value from current context by name
- `.and_return(:key)` — extract `:key` from script JSON output and expose as method

Script results are memoized — each script runs at most once per task execution.

### Sub-directives

```erb
<% use(:context).with(:task_id).and_return(:diff) %>
<%= use(:check_resources) %>
```

### Conditional logic

```erb
<% use(:sum).with(:input_numbers).and_return(:calculated_sum) %>

<% if calculated_sum > max_issues %>
  <%= use(:high_value).with(:calculated_sum) %>
<% else %>
  <%= use(:low_value).with(:calculated_sum) %>
<% end %>
```

### Mode-aware directives

Use `Frai.configuration.model` to adapt content to CLI vs API mode:

```erb
<% if Frai.configuration.model %>
<%# API mode: MCP tools already verified — proceed directly %>
<% else %>
<%# CLI mode: ask Claude to verify MCP access %>
Before starting, verify that required MCP tools are accessible.
<% end %>
```

---

## Scripts

Scripts receive `{ input: value }` as JSON on stdin and write a JSON hash to stdout:

```ruby
# tasks/analyze_item/scripts/fetch_data.rb
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

## Configuration

```ruby
# config/frai.rb
Frai.configure do |config|
  config.model   = ENV["LLM_MODEL"]     # nil = CLI mode, set = API mode
  config.api_key = ENV["LLM_API_KEY"]   # for the configured LLM provider
end
```

`config/frai.rb` automatically loads `.env` on startup.

---

## Environment variables

```bash
# .env — git-ignored
LLM_MODEL=claude-opus-4-6   # comment out for CLI mode
LLM_API_KEY=your_api_key

# MCP server credentials
JIRA_MCP_URL=https://...
GITLAB_TOKEN=your_token
```

Commit `.env.example` with empty values as a template for teammates.

---

## External MCP servers

**Step 1** — define the server in `mcp/*.rb`:

```ruby
# mcp/database.rb — stdio (local subprocess)
Frai::MCP.define :database do
  command "npx"
  args    ["-y", "@modelcontextprotocol/server-postgres", ENV["DATABASE_URL"]]
  env     DATABASE_URL: ENV["DATABASE_URL"]
end

# mcp/search.rb — HTTP (no auth)
Frai::MCP.define :search do
  url ENV["SEARCH_MCP_URL"]
end

# mcp/portal.rb — HTTP with OAuth (browser auth on first run)
Frai::MCP.define :portal do
  url   ENV["PORTAL_MCP_URL"]
  oauth true
end
```

**Step 2** — declare which MCPs each task needs in `task.yml`:

```ruby
class AnalyzeTask < BaseTask
  mcp :database
  mcp :search
  ...
end
```

**Step 3** — register with Claude CLI:

```bash
frai setup   # or: frai s
```

### OAuth HTTP MCP servers

When `oauth true` is set, frai manages tokens automatically:

- **First run**: browser opens for authentication. Token saved to `.frai_oauth_cache.json` (git-ignored).
- **Subsequent runs**: cached token used directly. Silent refresh attempted if expired.
- **Token expired (refresh fails)**: browser opens again.
- **For cron jobs**: authenticate once manually (`frai exec`), then cron uses the cached token.
- **Token cache expired**: if both access and refresh tokens are no longer valid, delete the cache file and re-authenticate:
  ```bash
  rm .frai_oauth_cache.json
  frai exec TaskName "param(value)"   # browser opens once
  ```

---

## Claude CLI integration

Each task gets its own slash command — created automatically by `frai gt`:

```bash
frai gt analyze_item
# → creates task files
# → creates .claude/commands/analyze_item.md
```

Invoke from Claude CLI **inside the project directory**:

```
/analyze_item query(some text)
/analyze_item query(some text) lang(en)
```

Arguments use `name(value)` format — names match params declared in `task.yml`.
Also supports `key:value` format: `/analyze_item query:some-text`

If the command fails, Claude reports the error and stops — it does not retry or guess parameters.

---

## Pipelines

```bash
frai gp review_pipeline
```

```ruby
class ReviewPipeline < BasePipeline
  def call(input)
    diff   = FetchDiffTask.call(input)
    review = CodeReviewTask.call(diff)
    review
  end
end
```

---

## Agents

```bash
frai ga research_agent
```

```ruby
class ResearchAgent < BaseAgent
  def call(input)
    data    = FetchDataTask.call(input)
    summary = SummarizeTask.call(data)
    summary
  end
end
```

---

## Removing a task

```bash
frai rt analyze_item   # short for: frai remove task
```

Removes the task directory and `.claude/commands/analyze_item.md`.

## Destroying a project

Before deleting the project directory, clean up external artifacts:

```bash
cd my_project
frai destroy
cd ..
rm -rf my_project
```

---

## Project discovery

`frai list` (alias: `frai l`) shows everything in the project at a glance:

```
Tasks:

  # Fetches and analyzes data from an external source
  analyze_item
    params:
      - query(required, String)
      - lang(optional, String, default: "en")
    mcp:
      - database (http/oauth)
      - search (stdio)
    directives:
      # Shared rules applied to all analyses
      - guidelines
    scripts:
      # Fetches raw data from the external API
      - fetch_data

MCP servers:

  # Hosted database MCP with OAuth
  - database  HTTP/oauth
      https://mcp.example.com/servers/abc123/mcp

Shared directives:
  - base
```

### Adding descriptions

**Task** — add `<desc>` tag at the top of `main.md.erb`:
```erb
<desc>Fetches and analyzes data from an external source</desc>

You are an expert analyst...
```

**Sub-directive** — same `<desc>` tag in the directive file:
```erb
<desc>Shared rules applied to all analyses</desc>

1) Always cite sources...
```

**Script** — `# desc:` comment at the top of the script (works for Ruby, Python, bash):
```python
# desc: Fetches raw data from the external API
import sys, json
...
```

**MCP server** — `desc` in the server definition:
```ruby
Frai::MCP.define :database do
  desc "Hosted database MCP with OAuth"
  url ENV["DATABASE_MCP_URL"]
  oauth true
end
```

**Pipeline / Agent** — `# desc:` comment before the class:
```ruby
# desc: Chains fetch and analysis tasks sequentially
class AnalysisPipeline < BasePipeline
  ...
end
```

---

## Logging

Write task output and errors to a log file — useful for cron jobs and automation:

```bash
frai exec AnalyzeItemTask "query(some text)" --log logs/analyze.log
```

Directories are created automatically if they don't exist. Each entry includes a timestamp and status:

```
[2026-06-06 08:00:00] [SUCCESS]
Analysis complete for query: some text...
------------------------------------------------------------
[2026-06-06 09:00:00] [ERROR]
Error: MCP :database OAuth failed — token expired
------------------------------------------------------------
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
| `frai setup` | Register `mcp/*.rb` servers with Claude CLI (`frai s`) |
| `frai destroy` | Clean up MCP servers and commands before deleting the project |
| `frai list` | List all tasks, MCPs, pipelines, agents and shared directives (`frai l`) |
| `frai exec CLASS_NAME [INPUT]` | Execute a task, pipeline, or agent (`frai e`) |
| `frai exec ... --log PATH` | Execute and write output/errors to log file |
| `frai console` | Interactive Ruby console with project loaded (`frai c`) |

---

## License

MIT
