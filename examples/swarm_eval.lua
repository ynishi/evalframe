#!/usr/bin/env lua
--[[
  examples/swarm_eval.lua — Swarm evaluation example

  Demonstrates the evalframe.swarm DSL for evaluating multi-agent
  Swarm systems. Uses a mock runner (no real LLM required).

  Covers:
    - Environment, action space, swarm config
    - Parametric variants (cross product)
    - Suite execution per variant
    - Variant comparison via Welch's t-test
    - Trace analysis helpers

  Run:
    lua examples/swarm_eval.lua
]]

package.path = "?.lua;?/init.lua;" .. package.path

local ef       = require("evalframe")
local sw       = require("evalframe.swarm")
local stats    = require("evalframe.eval.stats")
local analysis = sw.analysis

-- ============================================================
-- 1. Environment declaration
-- ============================================================

local env = sw.env "troubleshooting" {
  scenario = "memory_leak",
  services = { "user-service", "db-service", "cache-service" },
}

-- ============================================================
-- 2. Action space
-- ============================================================

local actions = sw.actions {
  sw.action "CheckStatus"    { description = "Check service health" },
  sw.action "ReadLogs"       { description = "Read service logs", target = "service" },
  sw.action "RestartService" { description = "Restart a service", target = "service" },
  sw.action "AnalyzeMetrics" { description = "Analyze performance metrics" },
}

-- ============================================================
-- 3. Mock runner (replace with real LLM-driven tick loop)
-- ============================================================

local function mock_runner(config)
  -- In production, replace this with your own runner:
  -- e.g. a Lua tick loop calling an LLM server,
  -- or a wrapper around your Swarm execution engine.

  local ticks = math.min(12, config.swarm.max_ticks)

  return {
    text        = "Resolved: memory leak in db-service",
    success     = true,
    ticks       = ticks,
    termination = "success",
    actions     = {
      { tick = 1,  worker = "w-0", action = "CheckStatus",    target = "user-service", result = "running" },
      { tick = 1,  worker = "w-1", action = "CheckStatus",    target = "db-service",   result = "degraded" },
      { tick = 3,  worker = "w-0", action = "ReadLogs",       target = "db-service",   result = "OOM detected" },
      { tick = 5,  worker = "w-1", action = "AnalyzeMetrics",                          result = "memory 98%" },
      { tick = 8,  worker = "w-0", action = "RestartService", target = "db-service",   result = "restarted" },
      { tick = 10, worker = "w-1", action = "CheckStatus",    target = "db-service",   result = "running" },
    },
    metrics = {
      task_completion = 1.0,
      throughput      = 3.2,
      error_count     = 0,
    },
  }
end

-- ============================================================
-- 4. Parametric variants (cross product)
-- ============================================================

local configs = ef.variants {
  base = {},

  ef.vary "scale" {
    { workers = 1, max_ticks = 30, name = "small" },
    { workers = 3, max_ticks = 20, name = "medium" },
  },

  ef.vary "strategy" {
    { strategy = "ucb1",   name = "ucb1" },
    { strategy = "greedy", name = "greedy" },
  },

  mode = "cross",  -- 2 x 2 = 4 variants
}

-- ============================================================
-- 5. Cases
-- ============================================================

local cases = {
  ef.case "memory_leak" {
    input    = "Diagnose and fix the memory leak in the cluster",
    expected = "Resolved",
  },
  ef.case "disk_full" {
    input    = "Investigate disk full alert on db-service",
    expected = "Resolved",
  },
}

-- ============================================================
-- 6. Run each variant, collect scores and traces
-- ============================================================

print("=== Swarm Evaluation ===\n")

local variant_scores = {}   -- { name = { score, score, ... } }
local variant_traces = {}   -- { name = { trace, trace, ... } }

for _, cfg in ipairs(configs) do
  local swarm_cfg = sw.swarm {
    workers   = cfg.workers,
    max_ticks = cfg.max_ticks,
    strategy  = cfg.strategy,
  }

  local provider = sw.provider(mock_runner, {
    env = env, actions = actions, swarm = swarm_cfg,
  })

  local report = ef.suite(cfg.name) {
    provider = provider,

    -- Graders
    ef.bind { sw.graders.completed, weight = 0.3 },
    ef.bind { sw.graders.efficiency { max_ticks = cfg.max_ticks, optimal_ticks = 5 }, weight = 0.2 },
    ef.bind { sw.graders.action_sequence { "CheckStatus", "ReadLogs", "RestartService" }, weight = 0.2 },
    ef.bind { sw.graders.metric("throughput", { min = 1.0 }), weight = 0.1 },

    -- Checkpoint: by tick 5, investigation should have started
    ef.bind { sw.graders.at_tick(5, function(snap)
      return snap.action_count >= 3
    end), weight = 0.2 },

    cases = cases,
  }:run()

  print(report:summary())
  print("")

  -- Collect scores for cross-variant comparison
  local scores = {}
  for _, r in ipairs(report.results) do
    scores[#scores + 1] = r.score
  end
  variant_scores[cfg.name] = scores

  -- Collect traces for analysis
  local traces = {}
  for _, r in ipairs(report.results) do
    traces[#traces + 1] = r.response
  end
  variant_traces[cfg.name] = traces
end

-- ============================================================
-- 7. Variant comparison via Welch's t-test
-- ============================================================

print("=== Variant Comparison (Welch's t-test) ===\n")

local names = {}
for _, cfg in ipairs(configs) do names[#names + 1] = cfg.name end

for i = 1, #names do
  for j = i + 1, #names do
    local a_name, b_name = names[i], names[j]
    local a = stats.describe(variant_scores[a_name])
    local b = stats.describe(variant_scores[b_name])
    local r = stats.welch_t(a, b)
    print(string.format(
      "  %s (mean=%.3f) vs %s (mean=%.3f): %s %s",
      a_name, a.mean, b_name, b.mean,
      r.significant and "SIGNIFICANT" or "not significant",
      r.direction ~= "equal" and ("(" .. r.direction .. ")") or ""
    ))
  end
end
print("")

-- ============================================================
-- 8. Trace analysis helpers
-- ============================================================

print("=== Trace Analysis ===\n")

for _, cfg in ipairs(configs) do
  local traces = variant_traces[cfg.name]
  if #traces > 0 then
    print(string.format("--- %s ---", cfg.name))

    -- Convergence: tick count distribution
    local conv = analysis.convergence(traces)
    print(string.format("  Convergence: mean=%.1f ticks, std=%.1f", conv.mean, conv.std_dev))

    -- Action sequence frequency (bigrams)
    local freq = analysis.action_sequences(traces, 2)
    print("  Action bigrams:")
    for seq, data in pairs(freq) do
      print(string.format("    %s: count=%d, success_rate=%.0f%%", seq, data.count, data.rate * 100))
    end

    -- Per-trace analysis on first trace
    local t = traces[1]
    local eff = analysis.exploration_efficiency(t)
    print(string.format("  Exploration: %d actions, %d unique (%.0f%% unique)",
      eff.total, eff.unique, eff.unique_ratio * 100))

    local coord = analysis.worker_coordination(t)
    print(string.format("  Workers: %d, action overlap=%.0f%%",
      coord.worker_count, coord.overlap_rate * 100))

    local qual = analysis.action_validity(t, function(a)
      return a.result ~= nil and a.result ~= "error"
    end)
    print(string.format("  Action validity: %d/%d (%.0f%%)",
      qual.valid, qual.total, qual.rate * 100))

    print("")
  end
end
