local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

describe("sw.trace", function()

  local function sample_trace()
    return sw.trace {
      text        = "resolved memory leak",
      success     = true,
      ticks       = 15,
      termination = "success",

      actions = {
        { tick = 1,  worker = "w-0", action = "CheckStatus",    target = "user-service", result = "running" },
        { tick = 2,  worker = "w-1", action = "ReadLogs",       target = "db-service",   result = "OOM detected" },
        { tick = 3,  worker = "w-0", action = "AnalyzeMetrics",                          result = "high memory" },
        { tick = 5,  worker = "w-1", action = "ReadLogs",       target = "cache-service", result = "ok" },
        { tick = 8,  worker = "w-0", action = "RestartService", target = "db-service",   result = "restarted" },
        { tick = 12, worker = "w-2", action = "CheckStatus",    target = "db-service",   result = "running" },
      },

      metrics = {
        task_completion = 1.0,
        action_count    = 6,
        error_count     = 1,
        throughput      = 3.5,
        coordination    = 0.8,
      },
    }
  end

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates trace from raw table", function()
      local t = sample_trace()
      assert.is_true(sw.is_trace(t))
      assert.equals("resolved memory leak", t.text)
      assert.equals(true, t.success)
      assert.equals(15, t.ticks)
      assert.equals("success", t.termination)
      assert.equals(6, #t.actions)
    end)

    it("preserves metrics", function()
      local t = sample_trace()
      assert.equals(1.0, t.metrics.task_completion)
      assert.equals(0.8, t.metrics.coordination)
    end)

    it("creates minimal trace", function()
      local t = sw.trace {
        text        = "",
        success     = false,
        ticks       = 0,
        termination = "failure",
        actions     = {},
        metrics     = {},
      }
      assert.is_true(sw.is_trace(t))
    end)
  end)

  -- ============================================================
  -- Validation
  -- ============================================================

  describe("validation", function()
    it("rejects non-table", function()
      h.assert_error_contains(function()
        sw.trace "bad"
      end, "must be a table")
    end)

    it("rejects missing actions", function()
      h.assert_error_contains(function()
        sw.trace {
          text = "", success = false, ticks = 0,
          termination = "failure", metrics = {},
        }
      end, "actions is required")
    end)

    it("rejects missing termination", function()
      h.assert_error_contains(function()
        sw.trace {
          text = "", success = false, ticks = 0,
          actions = {}, metrics = {},
        }
      end, "termination is required")
    end)

    it("rejects invalid termination value", function()
      h.assert_error_contains(function()
        sw.trace {
          text = "", success = false, ticks = 0,
          termination = "aborted", actions = {}, metrics = {},
        }
      end, "termination must be")
    end)
  end)

  -- ============================================================
  -- at_tick: snapshot at specific tick
  -- ============================================================

  describe("at_tick", function()
    it("returns actions up to given tick", function()
      local t = sample_trace()
      local snap = sw.trace_at_tick(t, 3)
      assert.equals(3, #snap.actions)
      assert.equals("CheckStatus", snap.actions[1].action)
      assert.equals("AnalyzeMetrics", snap.actions[3].action)
    end)

    it("returns action_count at tick", function()
      local t = sample_trace()
      local snap = sw.trace_at_tick(t, 5)
      assert.equals(4, snap.action_count)
    end)

    it("returns empty snapshot for tick 0", function()
      local t = sample_trace()
      local snap = sw.trace_at_tick(t, 0)
      assert.equals(0, #snap.actions)
      assert.equals(0, snap.action_count)
    end)

    it("returns all actions for tick >= max", function()
      local t = sample_trace()
      local snap = sw.trace_at_tick(t, 100)
      assert.equals(6, #snap.actions)
    end)

    it("includes per-action-name counts", function()
      local t = sample_trace()
      local snap = sw.trace_at_tick(t, 5)
      assert.equals(1, snap.action_counts["CheckStatus"])
      assert.equals(2, snap.action_counts["ReadLogs"])
      assert.equals(1, snap.action_counts["AnalyzeMetrics"])
      assert.is_nil(snap.action_counts["RestartService"])  -- tick 8, not yet
    end)
  end)

  -- ============================================================
  -- actions_by_worker
  -- ============================================================

  describe("actions_by_worker", function()
    it("filters actions for a specific worker", function()
      local t = sample_trace()
      local w0 = sw.trace_actions_by_worker(t, "w-0")
      assert.equals(3, #w0)
      for _, a in ipairs(w0) do
        assert.equals("w-0", a.worker)
      end
    end)

    it("returns empty for unknown worker", function()
      local t = sample_trace()
      local wx = sw.trace_actions_by_worker(t, "w-99")
      assert.equals(0, #wx)
    end)
  end)

  -- ============================================================
  -- action_count
  -- ============================================================

  describe("action_count", function()
    it("counts occurrences of named action", function()
      local t = sample_trace()
      assert.equals(2, sw.trace_action_count(t, "ReadLogs"))
      assert.equals(2, sw.trace_action_count(t, "CheckStatus"))
      assert.equals(1, sw.trace_action_count(t, "RestartService"))
    end)

    it("returns 0 for unknown action", function()
      local t = sample_trace()
      assert.equals(0, sw.trace_action_count(t, "NonExistent"))
    end)
  end)

  -- ============================================================
  -- has_action
  -- ============================================================

  describe("has_action", function()
    it("returns true when action exists", function()
      local t = sample_trace()
      assert.is_true(sw.trace_has_action(t, "ReadLogs"))
    end)

    it("returns false when action missing", function()
      local t = sample_trace()
      assert.is_false(sw.trace_has_action(t, "NonExistent"))
    end)
  end)
end)
