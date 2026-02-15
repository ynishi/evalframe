#!/usr/bin/env lua
--[[
  examples/math_eval.lua — Simple math evaluation example

  Run:
    lua examples/math_eval.lua

  This example uses a mock provider. Replace with a real provider
  (e.g., OpenAI, Anthropic) for actual LLM evaluation.
]]

package.path = "?.lua;?/init.lua;" .. package.path

local ef = require("evalframe")

-- ============================================================
-- Provider (mock for demo)
-- ============================================================

local function mock_math_llm(input)
  local answers = {
    ["What is 2+2?"]         = "4",
    ["What is 7*8?"]         = "56",
    ["What is 100/3?"]       = "33.33",
    ["What is sqrt(144)?"]   = "12",
    ["What is 2^10?"]        = "1024",
    ["Is 17 prime?"]         = "Yes, 17 is a prime number.",
    ["What is 0! (factorial)?"] = "1",
  }
  return { text = answers[input] or "I don't know" }
end

-- ============================================================
-- Cases
-- ============================================================

local case = ef.case

local cases = {
  case "addition"   { input = "What is 2+2?",       expected = "4",     tags = { "arithmetic", "basic" } },
  case "multiply"   { input = "What is 7*8?",        expected = "56",    tags = { "arithmetic", "basic" } },
  case "division"   { input = "What is 100/3?",      expected = "33.33", tags = { "arithmetic", "basic" } },
  case "sqrt"       { input = "What is sqrt(144)?",  expected = "12",    tags = { "arithmetic", "advanced" } },
  case "power"      { input = "What is 2^10?",       expected = "1024",  tags = { "arithmetic", "advanced" } },
  case "prime"      { input = "Is 17 prime?",         expected = "Yes",   tags = { "theory" } },
  case "factorial"  { input = "What is 0! (factorial)?", expected = "1",  tags = { "theory" } },
}

-- ============================================================
-- Suite
-- ============================================================

local s = ef.suite "math_eval" {
  provider = mock_math_llm,

  -- Binding 1: exact match (strict)
  ef.bind { ef.graders.exact_match, weight = 0.5 },

  -- Binding 2: contains (lenient)
  ef.bind { ef.graders.contains, weight = 0.5 },

  cases = cases,
}

-- ============================================================
-- Run & Report
-- ============================================================

local report = s:run()

print(report:summary())
print("")

-- Show failures
if #report.failures > 0 then
  print("Failures:")
  for _, f in ipairs(report.failures) do
    print(report.format_result(f))
  end
end
