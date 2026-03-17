local sw       = require("evalframe.swarm")
local analysis = sw.analysis
local h        = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("sw.analysis", function()

  -- Shared fixture: multiple traces for aggregate analysis
  local function make_traces()
    local t1 = sw.trace {
      text = "done", success = true, ticks = 10, termination = "success",
      actions = {
        { tick = 1, worker = "w-0", action = "Check",   result = "ok" },
        { tick = 3, worker = "w-1", action = "Read",    result = "OOM" },
        { tick = 5, worker = "w-0", action = "Restart", result = "ok" },
        { tick = 7, worker = "w-1", action = "Check",   result = "ok" },
      },
      metrics = { throughput = 3.0 },
    }

    local t2 = sw.trace {
      text = "done", success = true, ticks = 8, termination = "success",
      actions = {
        { tick = 1, worker = "w-0", action = "Check",   result = "ok" },
        { tick = 2, worker = "w-0", action = "Read",    result = "leak" },
        { tick = 4, worker = "w-1", action = "Restart", result = "ok" },
      },
      metrics = { throughput = 4.0 },
    }

    local t3 = sw.trace {
      text = "failed", success = false, ticks = 20, termination = "timeout",
      actions = {
        { tick = 1, worker = "w-0", action = "Check", result = "ok" },
        { tick = 5, worker = "w-0", action = "Check", result = "ok" },
      },
      metrics = { throughput = 0.5 },
    }

    return { t1, t2, t3 }
  end

  -- ============================================================
  -- action_sequences
  -- ============================================================

  describe("action_sequences", function()
    it("extracts bigram frequencies", function()
      local traces = make_traces()
      local freq = analysis.action_sequences(traces, 2)

      -- t1: Check,Read  Read,Restart  Restart,Check
      -- t2: Check,Read  Read,Restart
      -- t3: Check,Check
      expect(freq["Check,Read"]).to_not.equal(nil)
      expect(freq["Check,Read"].count).to.equal(2)
      expect(freq["Check,Read"].success).to.equal(2)  -- both t1 and t2 succeeded
      expect(freq["Check,Read"].rate).to.equal(1.0)
    end)

    it("tracks success rate per sequence", function()
      local traces = make_traces()
      local freq = analysis.action_sequences(traces, 2)

      -- Check,Check only appears in t3 (failure)
      if freq["Check,Check"] then
        expect(freq["Check,Check"].success).to.equal(0)
        expect(freq["Check,Check"].rate).to.equal(0)
      end
    end)

    it("defaults to trigrams", function()
      local traces = make_traces()
      local freq = analysis.action_sequences(traces)

      -- t1: Check,Read,Restart  Read,Restart,Check (trigrams)
      expect(freq["Check,Read,Restart"]).to_not.equal(nil)
    end)

    it("handles empty trace list", function()
      local freq = analysis.action_sequences({}, 2)
      expect(freq).to.equal({})
    end)

    it("handles trace shorter than ngram_size", function()
      local short = { sw.trace {
        termination = "success", ticks = 1,
        actions = { { tick = 1, worker = "w-0", action = "A", result = "ok" } },
      }}
      local freq = analysis.action_sequences(short, 3)
      expect(freq).to.equal({})
    end)

    it("rejects ngram_size < 1", function()
      h.assert_error_contains(function()
        analysis.action_sequences({}, 0)
      end, "ngram_size must be >= 1")
    end)

    it("deduplicates n-grams within the same trace", function()
      -- A,B appears twice in this trace but should count once per-trace
      local t = sw.trace {
        termination = "success", success = true, ticks = 5,
        actions = {
          { tick = 1, worker = "w-0", action = "A", result = "ok" },
          { tick = 2, worker = "w-0", action = "B", result = "ok" },
          { tick = 3, worker = "w-0", action = "A", result = "ok" },
          { tick = 4, worker = "w-0", action = "B", result = "ok" },
        },
      }
      local freq = analysis.action_sequences({ t }, 2)
      expect(freq["A,B"].count).to.equal(1)    -- 1 trace, not 2 occurrences
      expect(freq["A,B"].success).to.equal(1)
    end)
  end)

  -- ============================================================
  -- convergence
  -- ============================================================

  describe("convergence", function()
    it("computes tick distribution statistics", function()
      local traces = make_traces()
      local conv = analysis.convergence(traces)

      expect(conv.n).to.equal(3)
      -- mean of {10, 8, 20} = 12.67
      expect(conv.mean).to.equal(12.67, 0.1)
      expect(conv.min).to.equal(8)
      expect(conv.max).to.equal(20)
      expect(conv.ci_lower).to.be.a("number")
      expect(conv.ci_upper).to.be.a("number")
    end)

    it("measures first occurrence of target action", function()
      local traces = make_traces()
      local conv = analysis.convergence(traces, "Read")

      -- Read first at tick 3 (t1), tick 2 (t2), never (t3)
      expect(conv.n).to.equal(2)
      expect(conv.mean).to.equal(2.5, 0.01)
    end)

    it("skips traces without target action", function()
      local traces = make_traces()
      local conv = analysis.convergence(traces, "Restart")

      -- Restart at tick 5 (t1), tick 4 (t2), never (t3)
      expect(conv.n).to.equal(2)
    end)

    it("handles empty trace list", function()
      local conv = analysis.convergence({})
      expect(conv.n).to.equal(0)
    end)
  end)

  -- ============================================================
  -- exploration_efficiency
  -- ============================================================

  describe("exploration_efficiency", function()
    it("computes unique action ratio", function()
      local traces = make_traces()
      local eff = analysis.exploration_efficiency(traces[1])

      -- t1: Check, Read, Restart, Check -> 3 unique / 4 total
      expect(eff.total).to.equal(4)
      expect(eff.unique).to.equal(3)
      expect(eff.unique_ratio).to.equal(0.75, 0.01)
      expect(eff.duplicate_rate).to.equal(0.25, 0.01)
    end)

    it("all distinct actions", function()
      local t = sw.trace {
        termination = "success", ticks = 3,
        actions = {
          { tick = 1, worker = "w-0", action = "A", result = "ok" },
          { tick = 2, worker = "w-0", action = "B", result = "ok" },
          { tick = 3, worker = "w-0", action = "C", result = "ok" },
        },
      }
      local eff = analysis.exploration_efficiency(t)
      expect(eff.unique_ratio).to.equal(1.0)
      expect(eff.duplicate_rate).to.equal(0)
    end)

    it("handles empty actions", function()
      local t = sw.trace { termination = "failure", actions = {} }
      local eff = analysis.exploration_efficiency(t)
      expect(eff.total).to.equal(0)
      expect(eff.unique_ratio).to.equal(0)
    end)
  end)

  -- ============================================================
  -- worker_coordination
  -- ============================================================

  describe("worker_coordination", function()
    it("detects action overlap between workers", function()
      local traces = make_traces()
      local coord = analysis.worker_coordination(traces[1])

      -- t1: w-0 does Check,Restart; w-1 does Read,Check
      -- "Check" done by both w-0 and w-1 -> overlap
      expect(coord.worker_count).to.equal(2)
      expect(coord.overlap_rate > 0).to.equal(true)
    end)

    it("reports per-worker counts", function()
      local traces = make_traces()
      local coord = analysis.worker_coordination(traces[1])

      expect(coord.workers["w-0"].count).to.equal(2)  -- Check, Restart
      expect(coord.workers["w-1"].count).to.equal(2)  -- Read, Check
    end)

    it("no overlap for single worker", function()
      local t = sw.trace {
        termination = "success", ticks = 2,
        actions = {
          { tick = 1, worker = "w-0", action = "A", result = "ok" },
          { tick = 2, worker = "w-0", action = "B", result = "ok" },
        },
      }
      local coord = analysis.worker_coordination(t)
      expect(coord.worker_count).to.equal(1)
      expect(coord.overlap_rate).to.equal(0)
    end)

    it("handles empty actions", function()
      local t = sw.trace { termination = "failure", actions = {} }
      local coord = analysis.worker_coordination(t)
      expect(coord.worker_count).to.equal(0)
      expect(coord.overlap_rate).to.equal(0)
    end)
  end)

  -- ============================================================
  -- action_validity
  -- ============================================================

  describe("action_validity", function()
    it("computes validity rate with predicate", function()
      local traces = make_traces()
      local val = analysis.action_validity(traces[1], function(a)
        return a.result == "ok"
      end)

      -- t1: Check=ok, Read=OOM, Restart=ok, Check=ok -> 3/4 valid
      expect(val.total).to.equal(4)
      expect(val.valid).to.equal(3)
      expect(val.rate).to.equal(0.75, 0.01)
    end)

    it("all valid", function()
      local t = sw.trace {
        termination = "success", ticks = 2,
        actions = {
          { tick = 1, worker = "w-0", action = "A", result = "ok" },
          { tick = 2, worker = "w-0", action = "B", result = "ok" },
        },
      }
      local val = analysis.action_validity(t, function(_) return true end)
      expect(val.rate).to.equal(1.0)
    end)

    it("handles empty actions", function()
      local t = sw.trace { termination = "failure", actions = {} }
      local val = analysis.action_validity(t, function(_) return true end)
      expect(val.total).to.equal(0)
      expect(val.rate).to.equal(0)
    end)
  end)
end)
