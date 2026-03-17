local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
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
      expect(sw.is_trace(t)).to.equal(true)
      expect(t.text).to.equal("resolved memory leak")
      expect(t.success).to.equal(true)
      expect(t.ticks).to.equal(15)
      expect(t.termination).to.equal("success")
      expect(#t.actions).to.equal(6)
    end)

    it("preserves metrics", function()
      local t = sample_trace()
      expect(t.metrics.task_completion).to.equal(1.0)
      expect(t.metrics.coordination).to.equal(0.8)
    end)

    it("defensive-copies actions (caller mutation does not affect trace)", function()
      local acts = {
        { tick = 1, worker = "w-0", action = "Act", result = "ok" },
      }
      local t = sw.trace {
        termination = "success", actions = acts,
      }
      acts[1] = { tick = 99, worker = "w-9", action = "Mutated", result = "bad" }
      expect(t.actions[1].action).to.equal("Act")
      expect(#t.actions).to.equal(1)
    end)

    it("defensive-copies metrics (caller mutation does not affect trace)", function()
      local m = { score = 1.0 }
      local t = sw.trace {
        termination = "success", actions = {}, metrics = m,
      }
      m.score = 0.0
      m.injected = true
      expect(t.metrics.score).to.equal(1.0)
      expect(t.metrics.injected).to.equal(nil)
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
      expect(sw.is_trace(t)).to.equal(true)
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
      expect(t.text).to.equal("")
      expect(t.success).to.equal(false)
      expect(t.ticks).to.equal(0)
      expect(t.metrics).to.equal({})
    end)
  end)

  -- ============================================================
  -- Direct field access (validated by build)
  -- ============================================================

  describe("direct field access", function()
    it("success field is boolean", function()
      local t = sample_trace()
      expect(t.success).to.equal(true)

      local t2 = sw.trace { termination = "failure", actions = {} }
      expect(t2.success).to.equal(false)
    end)

    it("ticks field is number", function()
      local t = sample_trace()
      expect(t.ticks).to.equal(15)
    end)

    it("metrics are accessible by name", function()
      local t = sample_trace()
      expect(t.metrics.task_completion).to.equal(1.0)
      expect(t.metrics.coordination).to.equal(0.8)
      expect(t.metrics.nonexistent).to.equal(nil)
    end)

    it("actions are iterable", function()
      local t = sample_trace()
      local count = 0
      for _, a in ipairs(t.actions) do
        expect(a.action).to.be.a("string")
        expect(a.worker).to.be.a("string")
        expect(a.tick).to.be.a("number")
        count = count + 1
      end
      expect(count).to.equal(6)
    end)

    it("termination is a string", function()
      local t = sample_trace()
      expect(t.termination).to.equal("success")
    end)
  end)
end)
