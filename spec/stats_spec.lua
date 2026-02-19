local stats = require("evalframe.eval.stats")

describe("Stats", function()

  -- ============================================================
  -- Descriptive statistics
  -- ============================================================

  describe("describe", function()
    it("handles empty list", function()
      local s = stats.describe({})
      assert.equals(0, s.n)
      assert.equals(0, s.mean)
    end)

    it("computes single value", function()
      local s = stats.describe({ 5.0 })
      assert.equals(1, s.n)
      assert.equals(5.0, s.mean)
      assert.equals(0, s.std_dev)
      assert.equals(5.0, s.median)
    end)

    it("computes multiple values", function()
      local s = stats.describe({ 1, 2, 3, 4, 5 })
      assert.equals(5, s.n)
      assert.equals(3.0, s.mean)
      assert.equals(1, s.min)
      assert.equals(5, s.max)
      assert.equals(3, s.median)
    end)

    it("computes even count median", function()
      local s = stats.describe({ 1, 2, 3, 4 })
      assert.equals(2.5, s.median)
    end)

    it("computes std_dev", function()
      local s = stats.describe({ 2, 4, 4, 4, 5, 5, 7, 9 })
      -- sample std_dev of this dataset ≈ 2.138
      assert.near(2.138, s.std_dev, 0.01)
    end)
  end)

  -- ============================================================
  -- pass@k
  -- ============================================================

  describe("pass_at_k", function()
    it("returns 0 for no successes", function()
      assert.equals(0.0, stats.pass_at_k(10, 0, 1))
    end)

    it("returns 1 for all successes", function()
      assert.equals(1.0, stats.pass_at_k(10, 10, 1))
    end)

    it("pass@1 equals success rate", function()
      assert.near(0.5, stats.pass_at_k(10, 5, 1), 0.01)
    end)

    it("pass@5 is higher than pass@1 for partial success", function()
      local p1 = stats.pass_at_k(10, 3, 1)
      local p5 = stats.pass_at_k(10, 3, 5)
      assert.is_true(p5 > p1)
    end)

    it("handles k > n gracefully", function()
      local p = stats.pass_at_k(3, 1, 5)
      assert.equals(1.0, p)  -- at least 1 success exists
    end)

    it("is monotonic in k", function()
      local p1  = stats.pass_at_k(20, 5, 1)
      local p5  = stats.pass_at_k(20, 5, 5)
      local p10 = stats.pass_at_k(20, 5, 10)
      assert.is_true(p1 <= p5)
      assert.is_true(p5 <= p10)
    end)
  end)

  -- ============================================================
  -- Confidence interval
  -- ============================================================

  describe("ci_95", function()
    it("returns point estimate for n=1", function()
      local lo, hi = stats.ci_95({ n = 1, mean = 0.5, std_dev = 0 })
      assert.equals(0.5, lo)
      assert.equals(0.5, hi)
    end)

    it("interval shrinks with more data", function()
      local lo1, hi1 = stats.ci_95({ n = 5, mean = 0.5, std_dev = 0.2 })
      local lo2, hi2 = stats.ci_95({ n = 50, mean = 0.5, std_dev = 0.2 })
      assert.is_true((hi1 - lo1) > (hi2 - lo2))
    end)

    it("is symmetric around mean", function()
      local lo, hi = stats.ci_95({ n = 10, mean = 0.5, std_dev = 0.1 })
      assert.near(0.5, (lo + hi) / 2, 0.001)
    end)

    it("clamps lower bound to 0", function()
      local lo, _ = stats.ci_95({ n = 3, mean = 0.05, std_dev = 0.1 })
      assert.equals(0.0, lo)
    end)

    it("clamps upper bound to 1", function()
      local _, hi = stats.ci_95({ n = 3, mean = 0.95, std_dev = 0.1 })
      assert.equals(1.0, hi)
    end)
  end)

  -- ============================================================
  -- ci_95 unbounded mode
  -- ============================================================

  describe("ci_95 unbounded", function()
    it("does not clamp to [0,1] when unbounded", function()
      local lo, hi = stats.ci_95({ n = 5, mean = 10.0, std_dev = 2.0 }, { unbounded = true })
      assert.is_true(lo < 10.0)
      assert.is_true(hi > 10.0)
      assert.is_true(hi > 1.0)  -- would be clamped to 1.0 without unbounded
    end)

    it("still clamps by default (backward compatible)", function()
      local _, hi = stats.ci_95({ n = 3, mean = 0.95, std_dev = 0.1 })
      assert.equals(1.0, hi)
    end)
  end)

  -- ============================================================
  -- describe_with_ci
  -- ============================================================

  describe("describe_with_ci", function()
    it("combines describe and ci_95", function()
      local d = stats.describe_with_ci({ 0.5, 0.6, 0.7, 0.8, 0.9 })
      assert.equals(5, d.n)
      assert.equals(0.7, d.mean)
      assert.is_number(d.ci_lower)
      assert.is_number(d.ci_upper)
      assert.is_true(d.ci_lower <= d.mean)
      assert.is_true(d.ci_upper >= d.mean)
    end)

    it("passes opts to ci_95", function()
      local d = stats.describe_with_ci({ 10, 20, 30 }, { unbounded = true })
      assert.is_true(d.ci_upper > 1.0)  -- not clamped
    end)

    it("handles empty list", function()
      local d = stats.describe_with_ci({})
      assert.equals(0, d.n)
      assert.equals(0, d.ci_lower)
      assert.equals(0, d.ci_upper)
    end)
  end)

  -- ============================================================
  -- Welch's t-test
  -- ============================================================

  describe("welch_t", function()
    it("detects significant difference", function()
      local a = stats.describe({ 10, 11, 12, 13, 14 })
      local b = stats.describe({ 1, 2, 3, 4, 5 })
      local r = stats.welch_t(a, b)

      assert.is_true(r.significant)
      assert.equals("a>b", r.direction)
      assert.is_true(r.t_stat > 0)
      assert.is_true(r.df > 0)
    end)

    it("detects no significant difference for similar groups", function()
      local a = stats.describe({ 5.0, 5.1, 4.9, 5.0, 5.1 })
      local b = stats.describe({ 5.0, 4.9, 5.1, 5.0, 4.9 })
      local r = stats.welch_t(a, b)

      assert.is_false(r.significant)
    end)

    it("reports a<b when B is larger", function()
      local a = stats.describe({ 1, 2, 3 })
      local b = stats.describe({ 10, 11, 12 })
      local r = stats.welch_t(a, b)

      assert.equals("a<b", r.direction)
    end)

    it("handles equal groups", function()
      local a = stats.describe({ 5, 5, 5 })
      local b = stats.describe({ 5, 5, 5 })
      local r = stats.welch_t(a, b)

      assert.equals("equal", r.direction)
      assert.is_false(r.significant)
    end)

    it("handles insufficient data", function()
      local a = stats.describe({ 5 })
      local b = stats.describe({ 10 })
      local r = stats.welch_t(a, b)

      assert.equals("insufficient_data", r.direction)
      assert.is_false(r.significant)
    end)
  end)

  -- ============================================================
  -- Aggregate
  -- ============================================================

  describe("aggregate", function()
    it("handles empty results", function()
      local agg = stats.aggregate({})
      assert.equals(0, agg.total)
      assert.equals(0, agg.passed)
    end)

    it("computes pass rate", function()
      local results = {
        { score = 1.0, passed = true,  case = { tags = {} } },
        { score = 1.0, passed = true,  case = { tags = {} } },
        { score = 0.0, passed = false, case = { tags = {} } },
      }
      local agg = stats.aggregate(results)
      assert.equals(3, agg.total)
      assert.equals(2, agg.passed)
      assert.near(0.667, agg.pass_rate, 0.01)
    end)

    it("groups by tag", function()
      local results = {
        { score = 1.0, passed = true,  case = { tags = { "math" } } },
        { score = 0.0, passed = false, case = { tags = { "math" } } },
        { score = 1.0, passed = true,  case = { tags = { "code" } } },
      }
      local agg = stats.aggregate(results)
      assert.equals(0.5, agg.by_tag["math"].rate)
      assert.equals(1.0, agg.by_tag["code"].rate)
    end)
  end)
end)
