local ef = require("evalframe")
local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

describe("Swarm E2E", function()

  -- ============================================================
  -- Shared fixtures
  -- ============================================================

  local env = sw.env "troubleshooting" {
    scenario = "memory_leak",
    services = { "user-service", "db-service", "cache-service" },
  }

  local actions = sw.actions {
    sw.action "CheckStatus"    { description = "Check service health" },
    sw.action "ReadLogs"       { description = "Read service logs", target = "service" },
    sw.action "RestartService" { description = "Restart a service", target = "service" },
    sw.action "AnalyzeMetrics" { description = "Analyze performance metrics" },
  }

  local swarm_cfg = sw.swarm { workers = 3, managers = 1, max_ticks = 20 }

  -- Mock runner: simulates a successful troubleshooting session
  local function success_runner(_config)
    return {
      text        = "Resolved: memory leak in db-service caused by connection pool exhaustion",
      success     = true,
      ticks       = 12,
      termination = "success",
      actions     = {
        { tick = 1,  worker = "w-0", action = "CheckStatus",    target = "user-service",  result = "running" },
        { tick = 1,  worker = "w-1", action = "CheckStatus",    target = "db-service",    result = "degraded" },
        { tick = 2,  worker = "w-2", action = "CheckStatus",    target = "cache-service",  result = "running" },
        { tick = 3,  worker = "w-0", action = "ReadLogs",       target = "db-service",    result = "OOM detected at 14:32" },
        { tick = 4,  worker = "w-1", action = "AnalyzeMetrics",                           result = "memory usage 98%" },
        { tick = 6,  worker = "w-0", action = "ReadLogs",       target = "user-service",  result = "connection pool warnings" },
        { tick = 8,  worker = "w-1", action = "RestartService", target = "db-service",    result = "service restarted" },
        { tick = 10, worker = "w-0", action = "CheckStatus",    target = "db-service",    result = "running" },
        { tick = 12, worker = "w-2", action = "AnalyzeMetrics",                           result = "memory usage 45%" },
      },
      metrics = {
        task_completion = 1.0,
        action_count    = 9,
        error_count     = 0,
        throughput      = 3.2,
        coordination    = 0.85,
      },
    }
  end

  -- Mock runner: simulates a timeout
  local function timeout_runner(_config)
    return {
      text        = "Timeout: could not resolve issue",
      success     = false,
      ticks       = 20,
      termination = "timeout",
      actions     = {
        { tick = 1,  worker = "w-0", action = "CheckStatus", target = "user-service", result = "running" },
        { tick = 5,  worker = "w-0", action = "CheckStatus", target = "user-service", result = "running" },
        { tick = 10, worker = "w-0", action = "CheckStatus", target = "user-service", result = "running" },
      },
      metrics = {
        task_completion = 0.0,
        action_count    = 3,
        error_count     = 0,
        throughput      = 0.15,
      },
    }
  end

  -- ============================================================
  -- Full pipeline: provider -> suite -> graders -> report
  -- ============================================================

  describe("full pipeline", function()
    it("evaluates successful swarm run with multiple graders", function()
      local provider = sw.provider(success_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local report = ef.suite "troubleshooting_eval" {
        provider = provider,

        ef.bind { sw.graders.completed, weight = 0.4 },
        ef.bind { sw.graders.efficiency { max_ticks = 20, optimal_ticks = 5 }, weight = 0.2 },
        ef.bind { sw.graders.action_taken("ReadLogs"), weight = 0.1 },
        ef.bind { sw.graders.action_sequence { "CheckStatus", "ReadLogs", "RestartService" }, weight = 0.1 },
        ef.bind { sw.graders.metric("throughput", { min = 1.0 }), weight = 0.1 },
        ef.bind { sw.graders.at_tick(5, function(snap)
          return snap.action_count >= 3
        end), weight = 0.1 },

        cases = {
          ef.case "memory_leak" { input = "Diagnose and fix the memory leak in the cluster" },
        },
      }:run()

      assert.equals(1, report.aggregated.total)
      assert.is_true(report.aggregated.pass_rate >= 0)
      assert.is_true(report.results[1].score > 0.5)
    end)

    it("evaluates failed swarm run", function()
      local provider = sw.provider(timeout_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local report = ef.suite "timeout_eval" {
        provider = provider,

        ef.bind { sw.graders.completed, weight = 0.5 },
        ef.bind { sw.graders.efficiency { max_ticks = 20 }, weight = 0.3 },
        ef.bind { sw.graders.action_taken("RestartService"), weight = 0.2 },

        cases = {
          ef.case "memory_leak" { input = "Diagnose and fix the memory leak" },
        },
      }:run()

      assert.equals(1, report.aggregated.total)
      assert.equals(0, report.aggregated.passed)
      assert.equals(0.0, report.results[1].score)
    end)
  end)

  -- ============================================================
  -- Variants x Swarm: parametric multi-config evaluation
  -- ============================================================

  describe("variants integration", function()
    it("evaluates cross product of swarm configurations", function()
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

        mode = "cross",
      }

      assert.equals(4, #configs)

      local reports = {}
      for _, cfg in ipairs(configs) do
        local cfg_swarm = sw.swarm {
          workers   = cfg.workers,
          max_ticks = cfg.max_ticks,
          strategy  = cfg.strategy,
        }

        local provider = sw.provider(success_runner, {
          env = env, actions = actions, swarm = cfg_swarm,
        })

        local report = ef.suite(cfg.name) {
          provider = provider,
          ef.bind { sw.graders.completed },
          cases = {
            ef.case { input = "diagnose issue" },
          },
        }:run()

        reports[cfg.name] = report.aggregated.pass_rate
      end

      assert.equals(1.0, reports["small_ucb1"])
      assert.equals(1.0, reports["small_greedy"])
      assert.equals(1.0, reports["medium_ucb1"])
      assert.equals(1.0, reports["medium_greedy"])
    end)
  end)

  -- ============================================================
  -- DSL graders replacing custom graders (no trace helpers needed)
  -- ============================================================

  describe("DSL graders for common patterns", function()
    it("limits restart count via action_count grader", function()
      local provider = sw.provider(success_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local report = ef.suite "action_count_test" {
        provider = provider,
        ef.bind { sw.graders.action_count("RestartService", { max = 2 }) },
        cases = { ef.case { input = "test" } },
      }:run()

      -- success_runner has 1 restart, <= 2 -> pass
      assert.equals(1, report.aggregated.passed)
    end)

    it("checks all workers active via DSL grader", function()
      local provider = sw.provider(success_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local report = ef.suite "all_workers_test" {
        provider = provider,
        ef.bind { sw.graders.all_workers_active() },
        cases = { ef.case { input = "test" } },
      }:run()

      assert.equals(1, report.aggregated.passed)
    end)

    it("all_workers_active fails for single-worker trace", function()
      local provider = sw.provider(timeout_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local report = ef.suite "single_worker_test" {
        provider = provider,
        ef.bind { sw.graders.all_workers_active() },
        cases = { ef.case { input = "test" } },
      }:run()

      -- timeout_runner only uses w-0
      assert.equals(0, report.aggregated.passed)
    end)

    it("custom graders access trace fields directly", function()
      local provider = sw.provider(success_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      -- Direct field access in custom grader (no accessor helpers needed)
      local custom = ef.grader "direct_field" {
        check = function(resp, _case)
          return resp.success == true and resp.ticks < 15
        end,
      }

      local report = ef.suite "direct_field_test" {
        provider = provider,
        ef.bind { custom },
        cases = { ef.case { input = "test" } },
      }:run()

      assert.equals(1, report.aggregated.passed)
    end)
  end)

  -- ============================================================
  -- Runner error handling
  -- ============================================================

  describe("runner error handling", function()
    it("gracefully handles runner crash", function()
      local crashing_runner = function(_config)
        error("segfault in LLM server")
      end

      local provider = sw.provider(crashing_runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local report = ef.suite "crash_test" {
        provider = provider,
        ef.bind { ef.graders.not_empty },
        cases = { ef.case { input = "test" } },
      }:run()

      assert.equals(0, report.aggregated.passed)
      assert.truthy(report.results[1].response.error)
    end)
  end)
end)
