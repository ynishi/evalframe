# evalframe

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Lua](https://img.shields.io/badge/Lua-5.1%2B-blue.svg)](https://www.lua.org)

A Lua DSL for evaluating LLM outputs.

evalframe takes LLM responses and scores them through a declarative grading pipeline. Define what to check in Lua, let the runtime handle execution.

## Why Lua?

- **Startup in milliseconds** — no interpreter overhead, no venv
- **Tables = config AND code** — conditionals, loops, function composition where YAML/TOML can't reach
- **Embeddable in Rust** — via [mlua](https://github.com/mlua-rs/mlua), eval logic runs inside your Rust application
- **Minimal dependencies** — lua-cjson only

## Install

```bash
luarocks install lua-cjson
```

## Quick Start

```lua
local ef = require("evalframe")

local s = ef.suite "math" {
  provider = ef.providers.claude_cli { model = "haiku" },

  ef.bind { ef.graders.exact_match, weight = 0.5 },
  ef.bind { ef.graders.contains,    weight = 0.5 },

  cases = {
    ef.case "add" { input = "What is 2+2?",  expected = "4",  tags = { "basic" } },
    ef.case "mul" { input = "What is 7*8?",  expected = "56", tags = { "basic" } },
    ef.case "div" { input = "What is 10/3?", expected = "3.33", tags = { "basic" } },
  },
}

local report = s:run()
print(report:summary())
```

Output:

```
Suite: math
Cases: 3  Pass: 3  Fail: 0
pass@1: 1.00
Mean: 1.000  StdDev: 0.000  95% CI: [1.000, 1.000]

By tag:
  basic                3/3 (1.00)
```

## Architecture

```
Case (input + expected)
  |
Provider (call LLM)  ->  Response
  |
Grader (extract raw grade)  ->  Scorer (normalize to [0,1])
  |
Stats (pass@k, 95% CI)  ->  Report
```

### Core Concepts

| Concept      | Signature              | Description                          |
|--------------|------------------------|--------------------------------------|
| **Case**     | (data)                 | Input + expected output + metadata   |
| **Grader**   | check(resp, case) -> any | Extracts a raw grade from a response |
| **Scorer**   | score(raw) -> [0,1]    | Normalizes raw grade to [0,1]        |
| **Binding**  | (pair)                 | Pairs a Grader with a Scorer         |
| **Provider** | provider(input) -> response | Calls the LLM under test (user-supplied) |
| **Suite**    | :run() -> Report       | Composes everything into a runnable evaluation |

### Grader Tiers (Anthropic 3-layer principle)

| Tier | Type            | Use when                     | Examples                     |
|------|-----------------|------------------------------|------------------------------|
| 1    | Deterministic   | Always prefer first          | exact_match, contains, regex |
| 2    | LLM-as-Judge    | Deterministic can't reach    | rubric, yes_no, factuality   |
| 3    | Human           | Calibration                  | (future)                     |

## API Reference

### Cases

```lua
-- Minimal
ef.case { input = "What is 2+2?", expected = "4" }

-- Named with tags
ef.case "capital" { input = "Capital of Japan?", expected = {"Tokyo"}, tags = {"geo"} }

-- Open-ended (no expected)
ef.case { input = "Write a poem about the sea" }

-- Load from file
local cases = ef.load_cases("cases/math.lua")
```

Case files return a list of specs:

```lua
-- cases/math.lua
return {
  { input = "2+2?",  expected = "4",  tags = {"basic"} },
  { input = "3*3?",  expected = "9",  tags = {"basic"} },
}
```

### Built-in Graders (Tier 1)

```lua
local g = ef.graders

g.exact_match    -- response.text == expected (any of)
g.contains       -- response.text contains expected
g.starts_with    -- response.text starts with expected
g.regex          -- response.text matches Lua pattern (case.context.pattern)
g.json_valid     -- response.text is valid JSON
g.not_empty      -- response.text is non-empty
g.length         -- returns #response.text (pair with linear scorer)
g.latency        -- returns response.latency_ms (pair with inverse scorer)
```

### Custom Graders

```lua
local no_apology = ef.grader "no_apology" {
  check = function(resp, case)
    return not resp.text:lower():find("sorry")
  end
}
```

### LLM-as-Judge Graders (Tier 2)

A provider is **required** for all LLM-as-Judge graders.

```lua
local llm = ef.llm_graders
local provider = ef.providers.claude_cli { model = "sonnet" }

-- Rubric-based rating (returns number 1-5)
local quality = llm.rubric("Rate the answer for accuracy and clarity, 1-5", {
  provider = provider,
})
ef.bind { quality, ef.scorers.linear_1_5 }

-- Yes/No question (returns bool)
local polite = llm.yes_no("Is the response polite and professional?", {
  provider = provider,
})
ef.bind { polite }

-- Factuality check (returns number 1-5)
local factual = llm.factuality({ provider = provider })
ef.bind { factual, ef.scorers.linear_1_5 }
```

### Scorers

```lua
local s = ef.scorers

-- Built-in
s.bool            -- true->1.0, false->0.0
s.linear_1_5      -- [1,5] -> [0,1]
s.linear_1_10     -- [1,10] -> [0,1]
s.linear_0_100    -- [0,100] -> [0,1]
s.pass_50         -- >=0.5 -> 1.0
s.pass_80         -- >=0.8 -> 1.0
s.inverse_linear  -- lower is better (latency, token count)

-- Custom
ef.scorer "log_scale" {
  score = function(v)
    return math.log(v + 1) / math.log(11)
  end
}
```

### Bindings

```lua
-- Grader only (default bool scorer)
ef.bind { ef.graders.exact_match }

-- Grader + Scorer
ef.bind { ef.graders.length, ef.scorers.inverse("len", 500) }

-- Weighted (default weight = 1.0)
ef.bind { ef.graders.exact_match, weight = 0.7 }
ef.bind { ef.graders.contains,    weight = 0.3 }

-- Order doesn't matter (type-dispatched)
ef.bind { ef.scorers.linear_1_5, some_grader }
```

### Providers

Provider is a core requirement. Users must explicitly supply one.

```lua
-- Claude Code CLI
local p = ef.providers.claude_cli()
local p = ef.providers.claude_cli { model = "haiku" }
local p = ef.providers.claude_cli {
  model  = "sonnet",
  system = "You are a math tutor. Answer concisely.",
}

-- Mock (testing)
local p = ef.providers.mock.static("always this")
local p = ef.providers.mock.map({ ["2+2"] = "4", ["3*3"] = "9" })
local p = ef.providers.mock.fn(function(input) return "Echo: " .. input end)

-- Recording mock (captures inputs)
local p, log = ef.providers.mock.recording({ "a", "b", "c" })
p("hello")
print(log.calls[1])  -- "hello"

-- Custom provider (any function with the right signature)
local p = function(input)
  local resp = my_api_call(input)
  return { text = resp.content, model = "my-model" }
end
```

### Suite & Report

```lua
local s = ef.suite "my_eval" {
  provider = provider,
  ef.bind { ef.graders.exact_match, weight = 0.5 },
  ef.bind { ef.graders.contains,    weight = 0.5 },
  cases = {
    ef.case { input = "...", expected = "..." },
  },
}

local report = s:run()

-- Summary text
print(report:summary())

-- Programmatic access
report.aggregated.total       -- 50
report.aggregated.passed      -- 42
report.aggregated.pass_rate   -- 0.84
report.aggregated.pass_at_1   -- 0.84
report.aggregated.pass_at_5   -- 0.97
report.aggregated.scores.mean -- 0.82
report.aggregated.ci_95       -- { lower = 0.76, upper = 0.88 }
report.aggregated.by_tag      -- { math = { pass = 20, fail = 2, rate = 0.91 } }

-- Failures
for _, f in ipairs(report.failures) do
  print(report.format_result(f))
end
```

## Parametric Variants

Run the same suite across multiple configurations with `ef.variants`.

```lua
local configs = ef.variants {
  base = { temperature = 0.7 },

  ef.vary "model" {
    { model = "gpt-4",  name = "gpt4" },
    { model = "claude", name = "claude" },
  },

  ef.vary "temp" {
    { temperature = 0.0, name = "cold" },
    { temperature = 1.0, name = "hot" },
  },

  mode = "cross",  -- "cross" (default) or "zip"
}
-- → 4 variants: gpt4_cold, gpt4_hot, claude_cold, claude_hot

for _, cfg in ipairs(configs) do
  local report = ef.suite(cfg.name) {
    provider = make_provider(cfg),
    ef.bind { ef.graders.exact_match },
    cases = my_cases,
  }:run()
  print(report:summary())
end
```

- **cross** — Cartesian product of all dimensions (2 x 2 = 4)
- **zip** — 1:1 pairing, truncates to the shortest dimension
- Base values are overridden by dimension entries
- Entry `name` fields are joined with `_` to generate variant names

## Swarm Evaluation

`evalframe.swarm` extends evalframe for multi-agent Swarm evaluation.

```lua
local sw = require("evalframe.swarm")

-- 1. Environment
local env = sw.env "troubleshooting" {
  scenario = "memory_leak",
  services = { "user-service", "db-service" },
}

-- 2. Action space
local actions = sw.actions {
  sw.action "CheckStatus"    { description = "Check service health" },
  sw.action "ReadLogs"       { description = "Read service logs" },
  sw.action "RestartService" { description = "Restart a service" },
}

-- 3. Swarm config
local swarm_cfg = sw.swarm { workers = 3, max_ticks = 20, strategy = "ucb1" }

-- 4. Runner → Provider adapter
local provider = sw.provider(my_runner, {
  env = env, actions = actions, swarm = swarm_cfg,
})

-- 5. Suite with Swarm graders
local report = ef.suite "swarm_eval" {
  provider = provider,

  ef.bind { sw.graders.completed, weight = 0.3 },
  ef.bind { sw.graders.efficiency { max_ticks = 20, optimal_ticks = 5 }, weight = 0.2 },
  ef.bind { sw.graders.action_sequence { "CheckStatus", "ReadLogs", "RestartService" } },
  ef.bind { sw.graders.metric("throughput", { min = 1.0 }) },

  cases = { ef.case { input = "Diagnose the memory leak" } },
}:run()
```

### Runner Contract

The runner function receives a config table and returns a SwarmTrace:

```lua
local function my_runner(config)
  -- config.input, config.env, config.actions, config.swarm
  -- ... your tick loop / LLM orchestration here ...
  return {
    text        = "Resolved",
    success     = true,
    ticks       = 12,
    termination = "success",  -- "success" | "failure" | "timeout"
    actions     = {
      { tick = 1, worker = "w-0", action = "CheckStatus", result = "ok" },
    },
    metrics     = { task_completion = 1.0 },
  }
end
```

### Swarm Graders

| Grader | Description |
|--------|-------------|
| `sw.graders.completed` | `success == true` |
| `sw.graders.efficiency { max_ticks, optimal_ticks? }` | Linear score based on tick count |
| `sw.graders.action_taken(name)` | Action was executed at least once |
| `sw.graders.action_sequence { ... }` | Actions appeared in order |
| `sw.graders.metric(name, { min?, max? })` | Metric within threshold |
| `sw.graders.at_tick(n, fn)` | Check snapshot state at tick n |
| `sw.graders.after_action(name, fn)` | Check state after first occurrence |

### Trace Helpers

Access trace data through accessors (for use in custom graders):

```lua
sw.trace_succeeded(resp)              -- bool
sw.trace_tick_count(resp)             -- number
sw.trace_metric(resp, "throughput")   -- any | nil
sw.trace_action_count(resp, "Act")    -- number
sw.trace_has_action(resp, "Act")      -- bool
sw.trace_at_tick(resp, 5)             -- { actions, action_count, action_counts }
sw.trace_actions_by_worker(resp, "w-0")  -- action[]
sw.trace_find_first_action(resp, "Act")  -- tick number | nil
```

## Testing

```bash
busted spec/
```

## Directory Structure

```
evalframe/
  evalframe/
    init.lua              Public API
    std.lua               Stdlib shim (json/fs/time)
    variants.lua          Parametric variation generator
    model/                Core types: Case, Grader, Scorer, Binding
    eval/                 Pipeline: Suite, Runner, Stats, Report
    presets/              Built-in graders, scorers, LLM judges
    providers/            Claude CLI, mock
    swarm/                Swarm evaluation DSL
      init.lua            Module entry point
      env.lua             Environment declaration
      actions.lua         Action / ActionSpace
      config.lua          Swarm configuration
      trace.lua           SwarmTrace construction + query helpers
      provider.lua        Runner → Provider adapter
      graders.lua         Swarm-specific grader catalog
  spec/                   Tests (busted)
  examples/               Usage examples
  doc/                    Design documentation
```

## Requirements

- Lua 5.1+ (or LuaJIT)
- [lua-cjson](https://github.com/openresty/lua-cjson)
- [busted](https://github.com/lunarmodules/busted) (for running tests)
- claude CLI (for `claude_cli` provider)

## License

[MIT](LICENSE)
