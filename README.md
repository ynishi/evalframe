# evalframe

A Lua DSL for evaluating LLM outputs.

evalframe takes LLM responses and scores them through a declarative grading pipeline. Define what to check in Lua, let the runtime handle execution.

## Install

```bash
luarocks install lua-cjson   # required dependency
```

## Architecture

```
Case (input + expected)
  ↓
Provider (call LLM)  →  Response
  ↓
Grader (extract raw grade)  →  Scorer (normalize to [0,1])
  ↓
Stats (pass@k, 95% CI)  →  Report
```

### Core Concepts

| Concept      | Description                                     | Example                                    |
|--------------|-------------------------------------------------|--------------------------------------------|
| **Case**     | Input + expected output + metadata              | `case { input = "2+2?", expected = "4" }`  |
| **Grader**   | Extracts a raw grade from a response            | `grader "check" { check = fn }`            |
| **Scorer**   | Normalizes raw grade to [0,1]                   | `scorer "linear" { min = 1, max = 5 }`    |
| **Binding**  | Pairs a Grader with a Scorer                    | `bind { graders.exact_match }`             |
| **Provider** | Calls the LLM under test                        | `providers.claude_cli { model = "haiku" }` |
| **Suite**    | Composes everything into a runnable evaluation   | `suite "name" { provider, bindings, cases }` |

### Grader Tiers (Anthropic 3-layer principle)

| Tier | Type            | Use when                           | Examples                           |
|------|-----------------|------------------------------------|------------------------------------|
| 1    | Deterministic   | Always prefer first                | exact_match, contains, regex       |
| 2    | LLM-as-Judge    | Deterministic can't reach          | rubric, yes_no, factuality         |
| 3    | Human           | Calibration                        | (future)                           |

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

## API Usage

### Cases

```lua
local case = ef.case

-- Minimal
case { input = "What is 2+2?", expected = "4" }

-- Named with tags
case "capital" { input = "Capital of Japan?", expected = {"Tokyo", "東京"}, tags = {"geo"} }

-- Open-ended (no expected)
case { input = "Write a poem about the sea" }

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
local grader = ef.grader

-- Simple predicate
local no_apology = grader "no_apology" {
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
bind { quality, ef.scorers.linear_1_5 }

-- Yes/No question (returns bool)
local polite = llm.yes_no("Is the response polite and professional?", {
  provider = provider,
})
bind { polite }

-- Factuality check (returns number 1-5)
local factual = llm.factuality({ provider = provider })
bind { factual, ef.scorers.linear_1_5 }
```

### Scorers

```lua
local scorer = ef.scorer
local s = ef.scorers

-- Built-in
s.bool            -- true→1.0, false→0.0
s.linear_1_5      -- [1,5] → [0,1]
s.linear_1_10     -- [1,10] → [0,1]
s.linear_0_100    -- [0,100] → [0,1]
s.pass_50         -- >=0.5 → 1.0
s.pass_80         -- >=0.8 → 1.0
s.inverse_linear  -- lower is better (latency, token count)

-- Custom
scorer "log_scale" {
  score = function(v)
    return math.log(v + 1) / math.log(11)
  end
}
```

### Bindings

```lua
local bind = ef.bind

-- Grader only (default bool scorer)
bind { ef.graders.exact_match }

-- Grader + Scorer
bind { ef.graders.length, ef.scorers.inverse("len", 500) }

-- Weighted (default weight = 1.0)
bind { ef.graders.exact_match, weight = 0.7 }
bind { ef.graders.contains,    weight = 0.3 }

-- Order doesn't matter (type-dispatched)
bind { ef.scorers.linear_1_5, some_grader }
```

### Providers

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

### Suite

```lua
local suite = ef.suite

local s = suite "my_eval" {
  provider = provider,

  -- Bindings (positional)
  bind { graders.exact_match, weight = 0.5 },
  bind { graders.contains,    weight = 0.5 },

  -- Cases
  cases = {
    case { input = "...", expected = "..." },
  },
}

-- Run
local report = s:run()
```

### Report

```lua
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
  print("  Got: " .. f.response.text)
end

-- All results
for _, r in ipairs(report.results) do
  print(report.format_result(r))
end
```

## Directory Structure

```
evalframe/
  evalframe/
    init.lua              Public API
    std.lua               Stdlib shim (json/fs/time)
    model/                Core types: Case, Grader, Scorer, Binding
    eval/                 Pipeline: Suite, Runner, Stats, Report
    presets/              Built-in graders, scorers, LLM judges
    providers/            Claude CLI, mock
  spec/                   Tests (busted)
  examples/               Usage examples
  doc/                    Design documentation
```

## Requirements

- Lua 5.1+ (or LuaJIT)
- lua-cjson
- claude CLI (for claude_cli provider)
