local sw       = require("evalframe.swarm")
local analysis = sw.analysis
local h        = require("spec.spec_helper")

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
      assert.is_not_nil(freq["Check,Read"])
      assert.equals(2, freq["Check,Read"].count)
      assert.equals(2, freq["Check,Read"].success)  -- both t1 and t2 succeeded
      assert.equals(1.0, freq["Check,Read"].rate)
    end)

    it("tracks success rate per sequence", function()
      local traces = make_traces()
      local freq = analysis.action_sequences(traces, 2)

      -- Check,Check only appears in t3 (failure)
      if freq["Check,Check"] then
        assert.equals(0, freq["Check,Check"].success)
        assert.equals(0, freq["Check,Check"].rate)
      end
    end)

    it("defaults to trigrams", function()
      local traces = make_traces()
      local freq = analysis.action_sequences(traces)

      -- t1: Check,Read,Restart  Read,Restart,Check (trigrams)
      assert.is_not_nil(freq["Check,Read,Restart"])
    end)

    it("handles empty trace list", function()
      local freq = analysis.action_sequences({}, 2)
      assert.same({}, freq)
    end)

    it("handles trace shorter than ngram_size", function()
      local short = { sw.trace {
        termination = "success", ticks = 1,
        actions = { { tick = 1, worker = "w-0", action = "A", result = "ok" } },
      }}
      local freq = analysis.action_sequences(short, 3)
      assert.same({}, freq)
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
      assert.equals(1, freq["A,B"].count)    -- 1 trace, not 2 occurrences
      assert.equals(1, freq["A,B"].success)
    end)
  end)

  -- ============================================================
  -- convergence
  -- ============================================================

  describe("convergence", function()
    it("computes tick distribution statistics", function()
      local traces = make_traces()
      local conv = analysis.convergence(traces)

      assert.equals(3, conv.n)
      -- mean of {10, 8, 20} = 12.67
      assert.near(12.67, conv.mean, 0.1)
      assert.equals(8, conv.min)
      assert.equals(20, conv.max)
      assert.is_number(conv.ci_lower)
      assert.is_number(conv.ci_upper)
    end)

    it("measures first occurrence of target action", function()
      local traces = make_traces()
      local conv = analysis.convergence(traces, "Read")

      -- Read first at tick 3 (t1), tick 2 (t2), never (t3)
      assert.equals(2, conv.n)
      assert.near(2.5, conv.mean, 0.01)
    end)

    it("skips traces without target action", function()
      local traces = make_traces()
      local conv = analysis.convergence(traces, "Restart")

      -- Restart at tick 5 (t1), tick 4 (t2), never (t3)
      assert.equals(2, conv.n)
    end)

    it("handles empty trace list", function()
      local conv = analysis.convergence({})
      assert.equals(0, conv.n)
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
      assert.equals(4, eff.total)
      assert.equals(3, eff.unique)
      assert.near(0.75, eff.unique_ratio, 0.01)
      assert.near(0.25, eff.duplicate_rate, 0.01)
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
      assert.equals(1.0, eff.unique_ratio)
      assert.equals(0, eff.duplicate_rate)
    end)

    it("handles empty actions", function()
      local t = sw.trace { termination = "failure", actions = {} }
      local eff = analysis.exploration_efficiency(t)
      assert.equals(0, eff.total)
      assert.equals(0, eff.unique_ratio)
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
      assert.equals(2, coord.worker_count)
      assert.is_true(coord.overlap_rate > 0)
    end)

    it("reports per-worker counts", function()
      local traces = make_traces()
      local coord = analysis.worker_coordination(traces[1])

      assert.equals(2, coord.workers["w-0"].count)  -- Check, Restart
      assert.equals(2, coord.workers["w-1"].count)  -- Read, Check
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
      assert.equals(1, coord.worker_count)
      assert.equals(0, coord.overlap_rate)
    end)

    it("handles empty actions", function()
      local t = sw.trace { termination = "failure", actions = {} }
      local coord = analysis.worker_coordination(t)
      assert.equals(0, coord.worker_count)
      assert.equals(0, coord.overlap_rate)
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
      assert.equals(4, val.total)
      assert.equals(3, val.valid)
      assert.near(0.75, val.rate, 0.01)
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
      assert.equals(1.0, val.rate)
    end)

    it("handles empty actions", function()
      local t = sw.trace { termination = "failure", actions = {} }
      local val = analysis.action_validity(t, function(_) return true end)
      assert.equals(0, val.total)
      assert.equals(0, val.rate)
    end)
  end)
end)
