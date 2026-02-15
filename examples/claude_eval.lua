#!/usr/bin/env lua
--[[
  examples/claude_eval.lua — Real LLM evaluation via Claude Code CLI

  Run:
    lua examples/claude_eval.lua

  Requires: claude CLI installed and authenticated
]]

package.path = "?.lua;?/init.lua;" .. package.path

local ef = require("evalframe")

-- ============================================================
-- Provider: Claude Code CLI
-- ============================================================

local provider = ef.providers.claude_cli {
  model  = "haiku",
  system = "Answer concisely in one line. No explanation.",
}

-- ============================================================
-- Cases
-- ============================================================

local case = ef.case

local cases = {
  case "addition"  { input = "What is 2+2? Reply with just the number.",      expected = "4",     tags = { "math" } },
  case "capital"   { input = "Capital of France? Reply with just the name.",   expected = "Paris", tags = { "geography" } },
  case "language"  { input = "What language is 'Hola'? Reply with just the language name.", expected = "Spanish", tags = { "language" } },
}

-- ============================================================
-- Suite: deterministic grading
-- ============================================================

local s = ef.suite "claude_basic" {
  provider = provider,

  ef.bind { ef.graders.contains, weight = 1.0 },

  cases = cases,
}

-- ============================================================
-- Run & Report
-- ============================================================

print("Running eval against Claude CLI...")
print("")

local report = s:run()

print(report:summary())
print("")

-- Show all results
for _, r in ipairs(report.results) do
  print(report.format_result(r))
end

-- Show failures
if #report.failures > 0 then
  print("")
  print("--- Failures ---")
  for _, f in ipairs(report.failures) do
    print(string.format("  Input:    %s", f.case.input))
    print(string.format("  Expected: %s", table.concat(f.case.expected, " | ")))
    print(string.format("  Got:      %s", f.response.text))
    print("")
  end
end
