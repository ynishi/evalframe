local scorer  = require("evalframe.model.scorer")
local scorers = require("evalframe.presets.scorers")
local h       = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("Scorer", function()

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates with custom score function", function()
      local s = scorer "custom" {
        score = function(v) return v and 1.0 or 0.0 end
      }
      expect(scorer.is_scorer(s)).to.equal(true)
      expect(s.name).to.equal("custom")
    end)

    it("creates linear from min/max", function()
      local s = scorer "linear" { min = 0, max = 10 }
      expect(s.score(5)).to.equal(0.5)
      expect(s.score(0)).to.equal(0.0)
      expect(s.score(10)).to.equal(1.0)
    end)

    it("clamps linear to [0,1]", function()
      local s = scorer "linear" { min = 0, max = 10 }
      expect(s.score(-5)).to.equal(0.0)
      expect(s.score(15)).to.equal(1.0)
    end)

    it("creates threshold scorer", function()
      local s = scorer "thresh" { pass = 0.8 }
      expect(s.score(0.8)).to.equal(1.0)
      expect(s.score(1.0)).to.equal(1.0)
      expect(s.score(0.7)).to.equal(0.0)
    end)

    it("rejects same min and max", function()
      h.assert_error_contains(function()
        scorer "bad" { min = 5, max = 5 }
      end, "min and max must differ")
    end)

    it("rejects missing spec", function()
      h.assert_error_contains(function()
        scorer "bad" {}
      end, "requires 'score'")
    end)
  end)

  -- ============================================================
  -- Preset scorers
  -- ============================================================

  describe("presets", function()
    it("bool scorer handles true/false", function()
      expect(scorers.bool.score(true)).to.equal(1.0)
      expect(scorers.bool.score(false)).to.equal(0.0)
    end)

    it("bool scorer clamps numbers", function()
      expect(scorers.bool.score(0.5)).to.equal(0.5)
      expect(scorers.bool.score(1.5)).to.equal(1.0)
      expect(scorers.bool.score(-0.5)).to.equal(0.0)
    end)

    it("linear_1_5 maps 1-5 range", function()
      expect(scorers.linear_1_5.score(1)).to.equal(0.0)
      expect(scorers.linear_1_5.score(3)).to.equal(0.5)
      expect(scorers.linear_1_5.score(5)).to.equal(1.0)
    end)

    it("linear_1_10 maps 1-10 range", function()
      expect(scorers.linear_1_10.score(1)).to.equal(0.0)
      expect(scorers.linear_1_10.score(10)).to.equal(1.0)
    end)

    it("band_1_5 maps non-linear bands", function()
      expect(scorers.band_1_5.score(1)).to.equal(0.0)
      expect(scorers.band_1_5.score(2)).to.equal(0.0)
      expect(scorers.band_1_5.score(3)).to.equal(0.5)
      expect(scorers.band_1_5.score(4)).to.equal(1.0)
      expect(scorers.band_1_5.score(5)).to.equal(1.0)
    end)
  end)

  -- ============================================================
  -- Steps mode (constructor)
  -- ============================================================

  describe("steps mode", function()
    it("creates step-based scorer", function()
      local s = scorer "custom_band" {
        steps = { {0, 0.0}, {5, 0.5}, {8, 1.0} },
      }
      expect(scorer.is_scorer(s)).to.equal(true)
      expect(s.score(3)).to.equal(0.0)
      expect(s.score(5)).to.equal(0.5)
      expect(s.score(7)).to.equal(0.5)
      expect(s.score(8)).to.equal(1.0)
      expect(s.score(10)).to.equal(1.0)
    end)

    it("handles unordered steps (auto-sorted)", function()
      local s = scorer "unordered" {
        steps = { {8, 1.0}, {0, 0.0}, {5, 0.5} },
      }
      expect(s.score(3)).to.equal(0.0)
      expect(s.score(6)).to.equal(0.5)
      expect(s.score(9)).to.equal(1.0)
    end)

    it("rejects fewer than 2 steps", function()
      h.assert_error_contains(function()
        scorer "bad" { steps = { {0, 0.0} } }
      end, "steps must be table with >= 2")
    end)

    it("rejects invalid step format", function()
      h.assert_error_contains(function()
        scorer "bad" { steps = { {0, 0.0}, {"x", 1.0} } }
      end, "must be {threshold, score}")
    end)
  end)
end)
