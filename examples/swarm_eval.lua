#!/usr/bin/env lua
--[[
  examples/swarm_eval.lua — Swarm evaluation example

  Demonstrates the evalframe.swarm DSL for evaluating multi-agent
  Swarm systems. Uses a mock runner (no real LLM required).

  Run:
    lua examples/swarm_eval.lua
]]

package.path = "?.lua;?/init.lua;" .. package.path

local ef = require("evalframe")
local sw = require("evalframe.swarm")

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
  -- In production, this would be:
  --   return __rustlib.swarm.run(config)
  -- or a Lua tick loop calling an LLM server.

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
-- 6. Run each variant
-- ============================================================

print("=== Swarm Evaluation ===\n")

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
end
