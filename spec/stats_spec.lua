local stats = require("evalframe.eval.stats")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("Stats", function()

  -- ============================================================
  -- Descriptive statistics
  -- ============================================================

  describe("describe", function()
    it("handles empty list", function()
      local s = stats.describe({})
      expect(s.n).to.equal(0)
      expect(s.mean).to.equal(0)
    end)

    it("computes single value", function()
      local s = stats.describe({ 5.0 })
      expect(s.n).to.equal(1)
      expect(s.mean).to.equal(5.0)
      expect(s.std_dev).to.equal(0)
      expect(s.median).to.equal(5.0)
    end)

    it("computes multiple values", function()
      local s = stats.describe({ 1, 2, 3, 4, 5 })
      expect(s.n).to.equal(5)
      expect(s.mean).to.equal(3.0)
      expect(s.min).to.equal(1)
      expect(s.max).to.equal(5)
      expect(s.median).to.equal(3)
    end)

    it("computes even count median", function()
      local s = stats.describe({ 1, 2, 3, 4 })
      expect(s.median).to.equal(2.5)
    end)

    it("computes std_dev", function()
      local s = stats.describe({ 2, 4, 4, 4, 5, 5, 7, 9 })
      -- sample std_dev of this dataset ≈ 2.138
      expect(s.std_dev).to.equal(2.138, 0.01)
    end)
  end)

  -- ============================================================
  -- pass@k
  -- ============================================================

  describe("pass_at_k", function()
    it("returns 0 for no successes", function()
      expect(stats.pass_at_k(10, 0, 1)).to.equal(0.0)
    end)

    it("returns 1 for all successes", function()
      expect(stats.pass_at_k(10, 10, 1)).to.equal(1.0)
    end)

    it("pass@1 equals success rate", function()
      expect(stats.pass_at_k(10, 5, 1)).to.equal(0.5, 0.01)
    end)

    it("pass@5 is higher than pass@1 for partial success", function()
      local p1 = stats.pass_at_k(10, 3, 1)
      local p5 = stats.pass_at_k(10, 3, 5)
      expect(p5 > p1).to.equal(true)
    end)

    it("handles k > n gracefully", function()
      local p = stats.pass_at_k(3, 1, 5)
      expect(p).to.equal(1.0)  -- at least 1 success exists
    end)

    it("is monotonic in k", function()
      local p1  = stats.pass_at_k(20, 5, 1)
      local p5  = stats.pass_at_k(20, 5, 5)
      local p10 = stats.pass_at_k(20, 5, 10)
      expect(p1 <= p5).to.equal(true)
      expect(p5 <= p10).to.equal(true)
    end)
  end)

  -- ============================================================
  -- Confidence interval
  -- ============================================================

  describe("ci_95", function()
    it("returns point estimate for n=1", function()
      local lo, hi = stats.ci_95({ n = 1, mean = 0.5, std_dev = 0 })
      expect(lo).to.equal(0.5)
      expect(hi).to.equal(0.5)
    end)

    it("interval shrinks with more data", function()
      local lo1, hi1 = stats.ci_95({ n = 5, mean = 0.5, std_dev = 0.2 })
      local lo2, hi2 = stats.ci_95({ n = 50, mean = 0.5, std_dev = 0.2 })
      expect((hi1 - lo1) > (hi2 - lo2)).to.equal(true)
    end)

    it("is symmetric around mean", function()
      local lo, hi = stats.ci_95({ n = 10, mean = 0.5, std_dev = 0.1 })
      expect((lo + hi) / 2).to.equal(0.5, 0.001)
    end)

    it("clamps lower bound to 0", function()
      local lo, _ = stats.ci_95({ n = 3, mean = 0.05, std_dev = 0.1 })
      expect(lo).to.equal(0.0)
    end)

    it("clamps upper bound to 1", function()
      local _, hi = stats.ci_95({ n = 3, mean = 0.95, std_dev = 0.1 })
      expect(hi).to.equal(1.0)
    end)
  end)

  -- ============================================================
  -- ci_95 unbounded mode
  -- ============================================================

  describe("ci_95 unbounded", function()
    it("does not clamp to [0,1] when unbounded", function()
      local lo, hi = stats.ci_95({ n = 5, mean = 10.0, std_dev = 2.0 }, { unbounded = true })
      expect(lo < 10.0).to.equal(true)
      expect(hi > 10.0).to.equal(true)
      expect(hi > 1.0).to.equal(true)  -- would be clamped to 1.0 without unbounded
    end)

    it("still clamps by default (backward compatible)", function()
      local _, hi = stats.ci_95({ n = 3, mean = 0.95, std_dev = 0.1 })
      expect(hi).to.equal(1.0)
    end)
  end)

  -- ============================================================
  -- describe_with_ci
  -- ============================================================

  describe("describe_with_ci", function()
    it("combines describe and ci_95", function()
      local d = stats.describe_with_ci({ 0.5, 0.6, 0.7, 0.8, 0.9 })
      expect(d.n).to.equal(5)
      expect(d.mean).to.equal(0.7)
      expect(d.ci_lower).to.be.a("number")
      expect(d.ci_upper).to.be.a("number")
      expect(d.ci_lower <= d.mean).to.equal(true)
      expect(d.ci_upper >= d.mean).to.equal(true)
    end)

    it("passes opts to ci_95", function()
      local d = stats.describe_with_ci({ 10, 20, 30 }, { unbounded = true })
      expect(d.ci_upper > 1.0).to.equal(true)  -- not clamped
    end)

    it("handles empty list", function()
      local d = stats.describe_with_ci({})
      expect(d.n).to.equal(0)
      expect(d.ci_lower).to.equal(0)
      expect(d.ci_upper).to.equal(0)
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

      expect(r.significant).to.equal(true)
      expect(r.direction).to.equal("a>b")
      expect(r.t_stat > 0).to.equal(true)
      expect(r.df > 0).to.equal(true)
    end)

    it("detects no significant difference for similar groups", function()
      local a = stats.describe({ 5.0, 5.1, 4.9, 5.0, 5.1 })
      local b = stats.describe({ 5.0, 4.9, 5.1, 5.0, 4.9 })
      local r = stats.welch_t(a, b)

      expect(r.significant).to.equal(false)
    end)

    it("reports a<b when B is larger", function()
      local a = stats.describe({ 1, 2, 3 })
      local b = stats.describe({ 10, 11, 12 })
      local r = stats.welch_t(a, b)

      expect(r.direction).to.equal("a<b")
    end)

    it("handles equal groups", function()
      local a = stats.describe({ 5, 5, 5 })
      local b = stats.describe({ 5, 5, 5 })
      local r = stats.welch_t(a, b)

      expect(r.direction).to.equal("equal")
      expect(r.significant).to.equal(false)
    end)

    it("handles insufficient data", function()
      local a = stats.describe({ 5 })
      local b = stats.describe({ 10 })
      local r = stats.welch_t(a, b)

      expect(r.direction).to.equal("insufficient_data")
      expect(r.significant).to.equal(false)
    end)
  end)

  -- ============================================================
  -- Aggregate
  -- ============================================================

  describe("aggregate", function()
    it("handles empty results", function()
      local agg = stats.aggregate({})
      expect(agg.total).to.equal(0)
      expect(agg.passed).to.equal(0)
    end)

    it("computes pass rate", function()
      local results = {
        { score = 1.0, passed = true,  case = { tags = {} } },
        { score = 1.0, passed = true,  case = { tags = {} } },
        { score = 0.0, passed = false, case = { tags = {} } },
      }
      local agg = stats.aggregate(results)
      expect(agg.total).to.equal(3)
      expect(agg.passed).to.equal(2)
      expect(agg.pass_rate).to.equal(0.667, 0.01)
    end)

    it("groups by tag", function()
      local results = {
        { score = 1.0, passed = true,  case = { tags = { "math" } } },
        { score = 0.0, passed = false, case = { tags = { "math" } } },
        { score = 1.0, passed = true,  case = { tags = { "code" } } },
      }
      local agg = stats.aggregate(results)
      expect(agg.by_tag["math"].rate).to.equal(0.5)
      expect(agg.by_tag["code"].rate).to.equal(1.0)
    end)
  end)
end)
