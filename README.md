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

### Using frai in a Rails or host project

If you're integrating frai into an existing Ruby project (Rails, Sinatra, etc.):

**Option 1: Global installation** (recommended)
```bash
gem install frai
frai new my_project
```
Then require the project in your Rails config:
```ruby
# config/initializers/frai.rb
require_relative "../../path/to/my_project/config/frai"
```

**Option 2: Via Gemfile of a host project (Rails, etc.)**

If frai runs inside an existing Ruby/Rails project that uses Bundler, add it to that project's Gemfile:
```ruby
# Gemfile of the Rails/host project
gem "frai"
```
```bash
bundle install
bundle exec frai c          # console — only needed in bundler context
bundle exec frai e TaskName # exec  — only needed in bundler context
```

**Key point:** A standalone frai project (created with `frai new`) does **not** have `gem "frai"` in its Gemfile — frai must already be installed globally. The generated Gemfile only contains `rspec`.

---

## Getting started

```bash
frai new my_project
cd my_project
bundle install              # installs rspec
cp .env.example .env        # fill in your secrets
frai setup                  # register MCP servers with Claude CLI
frai gt analyze_item        # generate your first task
```

**Generated structure:**

```
my_project/
  Gemfile                # rspec
  .rspec
  tasks/
    base_task.rb
    analyze_item/                           # new task created
      task.rb                               # namespace + schema
      directives/
        main.md.erb                         # entry point
      scripts/
  pipelines/
    base_pipeline.rb
  agents/
    base_agent.rb
  applications/            # public entrypoints for external callers
  scripts/                 # shared scripts
  directives/              # shared prompt templates
    base.md.erb
  mcp/                     # external MCP server definitions
  config/
    frai.rb                # model, API key, autoload
  .env                     # local secrets — git-ignored
  .env.example             # template to commit
  .gitignore
  spec/
    spec_helper.rb
    conventions_spec.rb
```

**Key: Task naming convention**

When you run `frai gt analyze_item`:
- Creates folder: `tasks/analyze_item/`
- Creates file: `tasks/analyze_item/task.rb`
- Inside `task.rb` is a namespace: `module AnalyzeItem; class Task < BaseTask; end; end`
- **Invoke as**: `AnalyzeItem::Task.call(input)`
- Or CLI: `frai exec AnalyzeItem::Task "input"`

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
FRAI_ENV=production frai exec AnalyzeItem::Task "query(test)"
FRAI_ENV=development frai exec AnalyzeItem::Task "query(test)"
```

---

## Two modes of operation

Frai supports two fundamental modes — **CLI mode** and **API mode**. They control how the LLM is invoked.

### CLI mode (for development, prototyping, Claude.app users)

**Setup:** Leave `LLM_MODEL` unset in `.env`

```bash
# .env
# LLM_MODEL=...     (commented out)
# LLM_API_KEY=...   (not needed)
```

**How it works:**
- `frai exec` renders the prompt and **returns it as plain text**
- Claude.app reads the text and acts as the LLM
- No API calls are made by frai itself
- Useful for development, one-off requests, or users in Claude.app

**Example:**
```bash
frai exec CodeReview::Task "task_id(PDB-123)"
# Output: the rendered prompt (no API call)
# You paste this into Claude.app for analysis
```

### API mode (for production, cron jobs, automation)

**Setup:** Set `LLM_MODEL` and `LLM_API_KEY` in `.env`

```bash
# .env
LLM_MODEL=claude-opus-4-6
LLM_API_KEY=sk-ant-...
```

**How it works:**
- `frai exec` renders the prompt **and sends it to the LLM API via RubyLLM**
- Returns the LLM response directly
- Works in background jobs, cron, automation without user intervention
- Requires API credentials

**Example:**
```bash
FRAI_ENV=production frai exec CodeReview::Task "task_id(PDB-123)"
# Output: Claude's response (API call made internally)
```

### Development vs Production environments

| Env | LLM Calls | MCPs | Use Case |
|-----|-----------|------|----------|
| **development** | skipped | skipped | See prompts without API calls, test locally |
| **test** | skipped | skipped | Run specs, validate task structure |
| **production** | called | connected | Real API calls, connected MCP servers |

**Check which mode you're in:**
```ruby
Frai.configuration.env         # → :development, :test, or :production
Frai.configuration.model       # → nil (CLI mode) or "claude-opus-4-6" (API mode)
```

---

## Tasks

A task is the core unit — **one LLM call**. It validates input, runs scripts, renders a prompt, and optionally calls an LLM.

### Minimal

```ruby
module AnalyzeItem
  class Task < BaseTask
  end
end

AnalyzeItem::Task.call("some input")
```

### Schema DSL

All task declarations live inside `schema do ... end`:

| Command | Description |
|---------|-------------|
| `llm false` | Skip the LLM call — return the rendered prompt as a string. Default: `true` |
| `mcp :name` | Declare an MCP server dependency. Server must exist in `mcp/name.rb` |
| `const :name, value` | Define a constant available in directives as `<%= name %>` |
| `param :name, type: T, required: true` | Declare a required input parameter |
| `param :name, type: T, default: val` | Declare an optional input parameter with default |
| `use :name` | Include a sub-directive (`directives/name.md.erb`) |
| `run :name do ... end` | Declare a script (`scripts/name.rb`) with input/returns |

### Understanding `run` blocks (scripts)

Scripts are the mechanism for gathering external data. Each `run` block declares a script that will run as a subprocess and capture its result.

**Structure:**

```ruby
run :fetch_diff do
  input type: String              # What type of data the script receives
  returns :diff, type: String     # What field to capture from script output
end
```

**How it executes:**

1. Task receives input (e.g., `task_id: "PDB-123"`)
2. Script runs, receives `{ input: task_id }` as JSON on stdin
3. Script returns JSON like `{ "diff": "... code diff ..." }`
4. Frai captures the `:diff` field and exposes it in the directive as `diff` method
5. Template can use `<%= diff %>`

**In the directive:**

```erb
% run(:fetch_diff, params: :task_id, return: :diff)

Review this code:
<%= diff %>
```

- `params: :task_id` — pass the `task_id` param to the script
- `return: :diff` — extract the `diff` field from script's JSON output

### Full example

`task.rb` is the **contract** — params, constants, MCPs, sub-directives, and scripts are all declared in `schema do ... end`.

```ruby
module CodeReview
  class Task < BaseTask
    schema do
      mcp :jira
      mcp :gitlab

      const :max_issues, 10

      param :task_id,  type: String, required: true
      param :language, type: String, default: "english"

      use :code_style_guides do
        use :naming_rules
        use :formatting_rules
      end

      use :context do
        run :fetch_diff do
          input type: String
          returns :diff, type: String
        end
      end
    end
  end
end
```

### Task file structure and organization

When you run `frai gt code_review`, the generator creates:

```
tasks/
  code_review/                    # task name in snake_case
    task.rb                       # task contract (namespace + schema)
    directives/
      main.md.erb                 # entry point for LLM
      code_style_guides.md.erb    # sub-directive (referenced in main)
    scripts/
      analyze_diff.rb             # script (returns JSON to stdout)
      fetch_context.py            # can be any language
```

**Key points:**
- Each task lives in its own folder under `tasks/`
- `task.rb` contains the **namespace wrapper** and **schema declaration** — the contract
- Task name is derived from folder name: `code_review/` → `CodeReview::Task`
- Invoke as: `CodeReview::Task.call(task_id: "PDB-123")`
- All directives and scripts are discovered automatically by name

### Skipping the LLM call

By default every task sends the rendered prompt to the LLM. Set `llm false` to return the rendered prompt as a string without calling the LLM — useful for template-only tasks, intermediate pipeline steps, or debugging:

```ruby
module BuildReport
  class Task < BaseTask
    schema do
      llm false

      param :data, type: Hash, required: true

      run :process do
        input type: Hash
        returns :report, type: String
      end
    end
  end
end
```

| `llm` | Behaviour |
|-------|-----------|
| `true` (default) | render prompt → call LLM → return response |
| `false` | render prompt → return prompt string |

The Ruby class stays minimal — all structure comes from `schema do ... end` in `task.rb`.

**MCP validation rules:**
- Task declares `mcp :name` but `mcp/name.rb` is missing → error at startup
- `mcp/name.rb` exists but no task declares it → error at startup
- MCP not registered with Claude CLI (CLI mode) → error before LLM call
- MCP not accessible (API mode) → error before LLM call

---

## Directives

Directives are Markdown + ERB prompt templates. `main.md.erb` is always the entry point for the LLM call.

**Example:** `tasks/code_review/directives/main.md.erb`

### Available helpers in directives

**Variables** — access params, constants, and script results as plain methods:

```erb
You are a code reviewer.
Review this code:

<%= diff %>

Use these guidelines:
<%= guidelines %>
```

**Run a script** — capture result into a variable:

```erb
% run(:fetch_diff, params: :task_id, return: :diff)

Code changes:
<%= diff %>
```

**Use a sub-directive** — inline rendering:

```erb
<%= use(:summary, params: :analysis_result) %>
```

**Use a sub-directive** — capture into variable:

```erb
% use(:security_check, params: :diff, return: :security_issues)

Security findings:
<%= security_issues %>
```

**Conditional logic**:

```erb
% use(:analyze_diff, params: :diff, return: :result)

% if result.include?("critical")
  ALERT: Critical issues found!
  <%= use(:escalate_summary, params: :result) %>
% else
  Code is OK
% end
```

### Key points

| Concept | Syntax | Returns |
|---------|--------|---------|
| **Run script** | `% run(:name, params: :param, return: :var)` | "" (no text output) |
| **Inline sub-directive** | `<%= use(:name, params: :param) %>` | rendered text |
| **Capture sub-directive** | `% use(:name, params: :param, return: :var)` | "" (text in @var) |
| **Access variable** | `<%= var_name %>` | the value |
| **Params / constants / results** | `<%= param %>` | available as methods |

Type is declared in `task.rb` schema — not needed in templates.

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

**Step 2** — declare which MCPs each task needs in `schema do` inside `task.rb`:

```ruby
module Analyze
  class Task < BaseTask
    schema do
      mcp :database
      mcp :search

      # ...
    end
  end
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

Arguments use `name(value)` format — names match params declared in `schema do`.
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
    diff   = FetchDiff::Task.call(input)
    review = CodeReview::Task.call(diff)
    review
  end
end
```

---

## Applications

An application is the **stable public entrypoint** for a Frai project. External callers — Rails, other services, scripts — always call `Application.call(...)`. The internal implementation can change freely without affecting the caller.

```ruby
# applications/application.rb
class Application < Frai::Application
  def call(reviews:, language: "english")
    data     = FetchData::Task.call(reviews)
    response = Analyze::Task.call(language: language, data: data)
    response
  end
end

Application.call(reviews: [...], language: "english")
```

You can later add a step, swap a task, or change the flow — the external call site stays the same:

```ruby
# Before
def call(reviews:, language: "english")
  Analyze::Task.call(reviews)
end

# After — caller doesn't need to change
def call(reviews:, language: "english")
  normalized = Normalize::Task.call(reviews)
  analyzed   = Analyze::Task.call(normalized)
  Translate::Task.call(analyzed, language: language)
end
```

### Calling from Rails

Since it's plain Ruby, Rails can call the application class directly:

```ruby
# config/initializers/frai.rb
require Rails.root.join("lib/my_frai_project/config/frai")

# app/services/analysis_service.rb
result = Application.call(reviews: reviews, language: "english")
```

The frai project lives in `lib/` and is loaded via the initializer. All classes — `Application`, tasks, pipelines — become available as regular Ruby constants.

---

## Application vs Agent

| | Application | Agent |
|---|---|---|
| **Who decides what to call** | Developer (Ruby) | LLM at runtime |
| **Flow** | Fixed: step 1 → step 2 → output | Dynamic: branches, loops, retries |
| **LLM in control loop** | No | Yes |
| **Steps defined upfront** | Yes | No |
| **Use when** | Predictable, repeatable workflows | Open-ended tasks requiring reasoning |

### Application — deterministic chain
- Steps are plain Ruby — you decide the order
- LLM does not decide what to call next
- Fast, predictable, easy to test

### Agent — dynamic decision
- LLM decides which tools/tasks to call and when
- Can loop, branch, and call tools multiple times
- LLM is in the control loop

---

## Agents

```bash
frai ga research_agent
```

An agent is an **LLM-driven orchestrator** — it decides which tasks and tools to call based on intermediate results. Unlike an application, the flow is not fixed in advance.

```ruby
class ResearchAgent < BaseAgent
  def call(input)
    data    = FetchData::Task.call(input)
    summary = Summarize::Task.call(data)
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
frai exec AnalyzeItem::Task "query(some text)" --log logs/analyze.log
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

## Testing with RSpec

Frai projects include a `spec/` folder with a conventions spec out of the box. You can add your own specs there to test tasks, scripts, pipelines, and applications.

### Setup

Generated projects include `rspec` in their own `Gemfile` and a pre-generated `spec/spec_helper.rb`. No extra configuration needed — just run `bundle exec rspec` from the project root.

`spec/spec_helper.rb` is pre-generated:

```ruby
# spec/spec_helper.rb
ENV["FRAI_ENV"] = "test"

require_relative "../config/frai"

RSpec.configure do |config|
  config.after { Frai.reset! }
end
```

`FRAI_ENV=test` ensures all MCP servers are skipped and the LLM is never called — tasks return the rendered prompt instead of making API requests.

### Running specs

```bash
bundle exec rspec
```

Run a single file:

```bash
bundle exec rspec spec/tasks/code_review_spec.rb
```

Run a single example by line number:

```bash
bundle exec rspec spec/tasks/code_review_spec.rb:12
```

### Testing a task

```ruby
# spec/tasks/code_review_spec.rb
# frozen_string_literal: true
require "spec_helper"

RSpec.describe CodeReview::Task do
  it "renders the prompt with given params", :aggregate_failures do
    result = described_class.call(task_id: "PDB-123")

    expect(result).to include("PDB-123")
  end

  it "raises on missing required param" do
    expect { described_class.call(language: "english") }
      .to raise_error(Frai::MissingParam, /task_id/)
  end

  it "raises on wrong param type" do
    expect { described_class.call(task_id: 123) }
      .to raise_error(Frai::InvalidParam, /expected String/)
  end
end
```

### Testing an application

```ruby
# spec/applications/application_spec.rb
# frozen_string_literal: true
require "spec_helper"

RSpec.describe Application do
  it "calls tasks in sequence and returns a result", :aggregate_failures do
    result = described_class.call(reviews: [{ id: 1 }], language: "ru")

    expect(result).to be_a(String)
    expect(result).to include("reviews")
  end
end
```

### Testing a pipeline

```ruby
# spec/pipelines/review_pipeline_spec.rb
# frozen_string_literal: true
require "spec_helper"

RSpec.describe ReviewPipeline do
  it "chains tasks and returns final output" do
    result = described_class.call("input data")

    expect(result).to be_a(String)
  end
end
```

### Testing scripts in isolation

Scripts are subprocesses that read JSON from stdin and write JSON to stdout — test them directly with `Open3`. Use a named `subject` and group related assertions with `:aggregate_failures`:

```ruby
# spec/scripts/fetch_data_spec.rb
# frozen_string_literal: true
require "json"
require "open3"

SCRIPT_PATH = File.expand_path("../tasks/code_review/scripts/fetch_data.rb", __dir__)

def run_script(payload)
  stdout, stderr, status = Open3.capture3("ruby", SCRIPT_PATH, stdin_data: JSON.generate(payload))
  raise "Script failed:\n#{stderr}" unless status.success?

  JSON.parse(stdout, symbolize_names: true)
end

RSpec.describe "fetch_data script" do
  subject(:result) { run_script({ input: "PDB-123" }) }

  it "returns expected keys", :aggregate_failures do
    expect(result).to have_key(:diff)
    expect(result[:diff]).to include("PDB-123")
  end
end
```

Scripts can be written in any language (Ruby, Python, bash) — the spec only cares about the JSON contract.

### Key points

| Concern | How it works in test |
|---|---|
| LLM calls | Skipped — `FRAI_ENV=test` uses the Null adapter, returns rendered prompt |
| MCP servers | Skipped entirely in test/development |
| Scripts | Run as real subprocesses (they are standalone executables) |
| `rspec` availability | Dev dependency of frai — no changes to the host project's Gemfile needed |
| `Frai.reset!` | Resets configuration between tests — prevents state leakage |


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
