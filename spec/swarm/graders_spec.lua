local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

-- Reusable grader contract helper: grader.check(resp, case) → raw_grade
local function check(grader, trace, case)
  case = case or { input = "test", _tag = {} }
  return grader.check(trace, case)
end

-- Sample traces for testing
local function success_trace(overrides)
  local raw = {
    text        = "resolved",
    success     = true,
    ticks       = 10,
    termination = "success",
    actions     = {
      { tick = 1,  worker = "w-0", action = "CheckStatus",    result = "ok" },
      { tick = 3,  worker = "w-1", action = "ReadLogs",       result = "OOM" },
      { tick = 5,  worker = "w-0", action = "AnalyzeMetrics", result = "high mem" },
      { tick = 7,  worker = "w-1", action = "RestartService", result = "restarted" },
      { tick = 9,  worker = "w-0", action = "CheckStatus",    result = "ok" },
    },
    metrics = {
      task_completion = 1.0,
      throughput      = 3.5,
      error_count     = 1,
    },
  }
  if overrides then
    for k, v in pairs(overrides) do raw[k] = v end
  end
  return sw.trace(raw)
end

local function failure_trace()
  return sw.trace {
    text        = "failed",
    success     = false,
    ticks       = 20,
    termination = "timeout",
    actions     = {
      { tick = 1, worker = "w-0", action = "CheckStatus", result = "ok" },
    },
    metrics     = { task_completion = 0.0, error_count = 5 },
  }
end


describe("sw.graders", function()

  -- ============================================================
  -- completed: success == true → 1.0
  -- ============================================================

  describe("completed", function()
    it("returns true for successful trace", function()
      local grade = check(sw.graders.completed, success_trace())
      assert.is_true(grade)
    end)

    it("returns false for failed trace", function()
      local grade = check(sw.graders.completed, failure_trace())
      assert.is_false(grade)
    end)
  end)

  -- ============================================================
  -- efficiency: tick-based scoring
  -- ============================================================

  describe("efficiency", function()
    it("returns 1.0 when ticks <= optimal", function()
      local g = sw.graders.efficiency { max_ticks = 20, optimal_ticks = 10 }
      local grade = check(g, success_trace({ ticks = 5 }))
      assert.equals(1.0, grade)
    end)

    it("returns 0.0 when ticks >= max", function()
      local g = sw.graders.efficiency { max_ticks = 20, optimal_ticks = 5 }
      local grade = check(g, success_trace({ ticks = 20 }))
      assert.equals(0.0, grade)
    end)

    it("linearly interpolates between optimal and max", function()
      local g = sw.graders.efficiency { max_ticks = 20, optimal_ticks = 0 }
      local grade = check(g, success_trace({ ticks = 10 }))
      assert.near(0.5, grade, 0.01)
    end)

    it("returns 1.0 at exactly optimal_ticks", function()
      local g = sw.graders.efficiency { max_ticks = 20, optimal_ticks = 10 }
      local grade = check(g, success_trace({ ticks = 10 }))
      assert.equals(1.0, grade)
    end)

    it("rejects missing max_ticks", function()
      h.assert_error_contains(function()
        sw.graders.efficiency { optimal_ticks = 5 }
      end, "max_ticks is required")
    end)

    it("rejects optimal_ticks >= max_ticks", function()
      h.assert_error_contains(function()
        sw.graders.efficiency { max_ticks = 10, optimal_ticks = 10 }
      end, "optimal_ticks must be less than max_ticks")
    end)

    it("rejects optimal_ticks > max_ticks", function()
      h.assert_error_contains(function()
        sw.graders.efficiency { max_ticks = 5, optimal_ticks = 10 }
      end, "optimal_ticks must be less than max_ticks")
    end)

    it("defaults optimal_ticks to 0", function()
      local g = sw.graders.efficiency { max_ticks = 10 }
      local grade = check(g, success_trace({ ticks = 0 }))
      assert.equals(1.0, grade)
    end)
  end)

  -- ============================================================
  -- action_taken: check if specific action was executed
  -- ============================================================

  describe("action_taken", function()
    it("returns true when action exists", function()
      local g = sw.graders.action_taken("ReadLogs")
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("returns false when action missing", function()
      local g = sw.graders.action_taken("NonExistent")
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)
  end)

  -- ============================================================
  -- action_sequence: ordered action check
  -- ============================================================

  describe("action_sequence", function()
    it("returns true when actions appear in order", function()
      local g = sw.graders.action_sequence { "CheckStatus", "ReadLogs", "RestartService" }
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("returns false when order is violated", function()
      local g = sw.graders.action_sequence { "RestartService", "ReadLogs" }
      -- RestartService at tick 7, ReadLogs at tick 3 (no ReadLogs after tick 7)
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("returns true for single-action sequence", function()
      local g = sw.graders.action_sequence { "ReadLogs" }
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("returns false when action is missing from trace", function()
      local g = sw.graders.action_sequence { "CheckStatus", "NonExistent" }
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("rejects empty sequence", function()
      h.assert_error_contains(function()
        sw.graders.action_sequence {}
      end, "at least 1 action")
    end)

    it("includes sequence in grader name", function()
      local g = sw.graders.action_sequence { "A", "B", "C" }
      assert.equals("sw.action_sequence:A,B,C", g.name)
    end)
  end)

  -- ============================================================
  -- action_count: threshold-based action count
  -- ============================================================

  describe("action_count", function()
    it("passes when count within max", function()
      local g = sw.graders.action_count("RestartService", { max = 2 })
      local grade = check(g, success_trace())
      assert.is_true(grade)  -- 1 restart <= 2
    end)

    it("fails when count exceeds max", function()
      local g = sw.graders.action_count("CheckStatus", { max = 1 })
      local grade = check(g, success_trace())
      assert.is_false(grade)  -- 2 CheckStatus > 1
    end)

    it("passes when count meets min", function()
      local g = sw.graders.action_count("ReadLogs", { min = 1 })
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("fails when count below min", function()
      local g = sw.graders.action_count("RestartService", { min = 3 })
      local grade = check(g, success_trace())
      assert.is_false(grade)  -- 1 restart < 3
    end)

    it("supports min and max together", function()
      local g = sw.graders.action_count("CheckStatus", { min = 1, max = 5 })
      local grade = check(g, success_trace())
      assert.is_true(grade)  -- 2 CheckStatus in [1,5]
    end)

    it("returns true for zero count when max >= 0", function()
      local g = sw.graders.action_count("NonExistent", { max = 5 })
      local grade = check(g, success_trace())
      assert.is_true(grade)  -- 0 <= 5
    end)

    it("rejects missing thresholds", function()
      h.assert_error_contains(function()
        sw.graders.action_count("X", {})
      end, "min or max is required")
    end)
  end)

  -- ============================================================
  -- all_workers_active: distinct worker participation check
  -- ============================================================

  describe("all_workers_active", function()
    it("passes when multiple workers contribute (default >= 2)", function()
      local g = sw.graders.all_workers_active()
      local grade = check(g, success_trace())
      assert.is_true(grade)  -- w-0 and w-1 both active
    end)

    it("fails for single-worker trace (default >= 2)", function()
      local g = sw.graders.all_workers_active()
      local grade = check(g, failure_trace())
      assert.is_false(grade)  -- only w-0
    end)

    it("fails for empty actions", function()
      local g = sw.graders.all_workers_active()
      local t = sw.trace {
        termination = "failure", actions = {},
      }
      local grade = check(g, t)
      assert.is_false(grade)
    end)

    it("passes when worker count meets explicit threshold", function()
      local g = sw.graders.all_workers_active { workers = 2 }
      local grade = check(g, success_trace())
      assert.is_true(grade)  -- w-0 and w-1
    end)

    it("fails when worker count below explicit threshold", function()
      local g = sw.graders.all_workers_active { workers = 3 }
      local grade = check(g, success_trace())
      assert.is_false(grade)  -- only w-0 and w-1 (2 < 3)
    end)
  end)

  -- ============================================================
  -- metric: threshold-based metric check
  -- ============================================================

  describe("metric", function()
    it("passes when metric meets min threshold", function()
      local g = sw.graders.metric("throughput", { min = 2.0 })
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("fails when metric below min", function()
      local g = sw.graders.metric("throughput", { min = 10.0 })
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("passes when metric meets max threshold", function()
      local g = sw.graders.metric("error_count", { max = 3 })
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("fails when metric exceeds max", function()
      local g = sw.graders.metric("error_count", { max = 0 })
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("supports both min and max together", function()
      local g = sw.graders.metric("throughput", { min = 1.0, max = 5.0 })
      local grade = check(g, success_trace())  -- throughput = 3.5
      assert.is_true(grade)
    end)

    it("fails when metric missing from trace", function()
      local g = sw.graders.metric("nonexistent", { min = 0 })
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("rejects missing thresholds", function()
      h.assert_error_contains(function()
        sw.graders.metric("x", {})
      end, "min or max is required")
    end)
  end)

  -- ============================================================
  -- at_tick: post-hoc checkpoint grader
  -- ============================================================

  describe("at_tick", function()
    it("passes snapshot at given tick to check function", function()
      local g = sw.graders.at_tick(3, function(snap)
        return snap.action_count >= 2
      end)
      local grade = check(g, success_trace())
      -- At tick 3: CheckStatus(1) + ReadLogs(3) = 2 actions
      assert.is_true(grade)
    end)

    it("fails when check function returns false", function()
      local g = sw.graders.at_tick(1, function(snap)
        return snap.action_count >= 5
      end)
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("provides action_counts in snapshot", function()
      local g = sw.graders.at_tick(5, function(snap)
        return (snap.action_counts["CheckStatus"] or 0) >= 1
           and (snap.action_counts["ReadLogs"] or 0) >= 1
      end)
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)
  end)

  -- ============================================================
  -- after_action: check state right after a specific action
  -- ============================================================

  describe("after_action", function()
    it("checks state after first occurrence of action", function()
      local g = sw.graders.after_action("ReadLogs", function(snap)
        return snap.action_count >= 2
      end)
      -- ReadLogs first at tick 3, by then: CheckStatus(1) + ReadLogs(3) = 2 actions
      local grade = check(g, success_trace())
      assert.is_true(grade)
    end)

    it("returns false when action never occurred", function()
      local g = sw.graders.after_action("NonExistent", function(_snap)
        return true
      end)
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)

    it("returns false when check function fails", function()
      local g = sw.graders.after_action("CheckStatus", function(snap)
        return snap.action_count >= 100
      end)
      local grade = check(g, success_trace())
      assert.is_false(grade)
    end)
  end)
end)
