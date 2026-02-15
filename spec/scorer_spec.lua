local scorer  = require("evalframe.model.scorer")
local scorers = require("evalframe.presets.scorers")
local h       = require("spec.spec_helper")

describe("Scorer", function()

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates with custom score function", function()
      local s = scorer "custom" {
        score = function(v) return v and 1.0 or 0.0 end
      }
      assert.is_true(scorer.is_scorer(s))
      assert.equals("custom", s.name)
    end)

    it("creates linear from min/max", function()
      local s = scorer "linear" { min = 0, max = 10 }
      assert.equals(0.5, s.score(5))
      assert.equals(0.0, s.score(0))
      assert.equals(1.0, s.score(10))
    end)

    it("clamps linear to [0,1]", function()
      local s = scorer "linear" { min = 0, max = 10 }
      assert.equals(0.0, s.score(-5))
      assert.equals(1.0, s.score(15))
    end)

    it("creates threshold scorer", function()
      local s = scorer "thresh" { pass = 0.8 }
      assert.equals(1.0, s.score(0.8))
      assert.equals(1.0, s.score(1.0))
      assert.equals(0.0, s.score(0.7))
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
      assert.equals(1.0, scorers.bool.score(true))
      assert.equals(0.0, scorers.bool.score(false))
    end)

    it("bool scorer clamps numbers", function()
      assert.equals(0.5, scorers.bool.score(0.5))
      assert.equals(1.0, scorers.bool.score(1.5))
      assert.equals(0.0, scorers.bool.score(-0.5))
    end)

    it("linear_1_5 maps 1-5 range", function()
      assert.equals(0.0, scorers.linear_1_5.score(1))
      assert.equals(0.5, scorers.linear_1_5.score(3))
      assert.equals(1.0, scorers.linear_1_5.score(5))
    end)

    it("linear_1_10 maps 1-10 range", function()
      assert.equals(0.0, scorers.linear_1_10.score(1))
      assert.equals(1.0, scorers.linear_1_10.score(10))
    end)

    it("band_1_5 maps non-linear bands", function()
      assert.equals(0.0, scorers.band_1_5.score(1))
      assert.equals(0.0, scorers.band_1_5.score(2))
      assert.equals(0.5, scorers.band_1_5.score(3))
      assert.equals(1.0, scorers.band_1_5.score(4))
      assert.equals(1.0, scorers.band_1_5.score(5))
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
      assert.is_true(scorer.is_scorer(s))
      assert.equals(0.0, s.score(3))
      assert.equals(0.5, s.score(5))
      assert.equals(0.5, s.score(7))
      assert.equals(1.0, s.score(8))
      assert.equals(1.0, s.score(10))
    end)

    it("handles unordered steps (auto-sorted)", function()
      local s = scorer "unordered" {
        steps = { {8, 1.0}, {0, 0.0}, {5, 0.5} },
      }
      assert.equals(0.0, s.score(3))
      assert.equals(0.5, s.score(6))
      assert.equals(1.0, s.score(9))
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
