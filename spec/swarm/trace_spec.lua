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

    it("defensive-copies actions (caller mutation does not affect trace)", function()
      local acts = {
        { tick = 1, worker = "w-0", action = "Act", result = "ok" },
      }
      local t = sw.trace {
        termination = "success", actions = acts,
      }
      acts[1] = { tick = 99, worker = "w-9", action = "Mutated", result = "bad" }
      assert.equals("Act", t.actions[1].action)
      assert.equals(1, #t.actions)
    end)

    it("defensive-copies metrics (caller mutation does not affect trace)", function()
      local m = { score = 1.0 }
      local t = sw.trace {
        termination = "success", actions = {}, metrics = m,
      }
      m.score = 0.0
      m.injected = true
      assert.equals(1.0, t.metrics.score)
      assert.is_nil(t.metrics.injected)
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

    it("rejects action record with non-number tick", function()
      h.assert_error_contains(function()
        sw.trace {
          termination = "success",
          actions = { { tick = "one", worker = "w-0", action = "Act" } },
        }
      end, "actions[1].tick must be number")
    end)

    it("rejects action record with missing worker", function()
      h.assert_error_contains(function()
        sw.trace {
          termination = "success",
          actions = { { tick = 1, action = "Act" } },
        }
      end, "actions[1].worker must be string")
    end)

    it("rejects action record with missing action name", function()
      h.assert_error_contains(function()
        sw.trace {
          termination = "success",
          actions = { { tick = 1, worker = "w-0" } },
        }
      end, "actions[1].action must be string")
    end)

    it("rejects non-table action record", function()
      h.assert_error_contains(function()
        sw.trace {
          termination = "success",
          actions = { "not a table" },
        }
      end, "actions[1] must be a table")
    end)

    it("applies defaults for optional fields", function()
      local t = sw.trace {
        termination = "failure",
        actions     = {},
      }
      assert.equals("", t.text)
      assert.equals(false, t.success)
      assert.equals(0, t.ticks)
      assert.same({}, t.metrics)
    end)
  end)

  -- ============================================================
  -- Direct field access (validated by build)
  -- ============================================================

  describe("direct field access", function()
    it("success field is boolean", function()
      local t = sample_trace()
      assert.is_true(t.success)

      local t2 = sw.trace { termination = "failure", actions = {} }
      assert.is_false(t2.success)
    end)

    it("ticks field is number", function()
      local t = sample_trace()
      assert.equals(15, t.ticks)
    end)

    it("metrics are accessible by name", function()
      local t = sample_trace()
      assert.equals(1.0, t.metrics.task_completion)
      assert.equals(0.8, t.metrics.coordination)
      assert.is_nil(t.metrics.nonexistent)
    end)

    it("actions are iterable", function()
      local t = sample_trace()
      local count = 0
      for _, a in ipairs(t.actions) do
        assert.is_string(a.action)
        assert.is_string(a.worker)
        assert.is_number(a.tick)
        count = count + 1
      end
      assert.equals(6, count)
    end)

    it("termination is a string", function()
      local t = sample_trace()
      assert.equals("success", t.termination)
    end)
  end)
end)
