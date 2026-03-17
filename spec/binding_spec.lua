local bind    = require("evalframe.model.binding")
local grader  = require("evalframe.model.grader")
local scorer  = require("evalframe.model.scorer")
local graders = require("evalframe.presets.graders")
local scorers = require("evalframe.presets.scorers")
local h       = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("Binding", function()

  local g = graders.exact_match
  local s = scorers.linear_1_5

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates with grader + scorer", function()
      local b = bind { g, s }
      expect(bind.is_binding(b)).to.equal(true)
      expect(b.grader).to.equal(g)
      expect(b.scorer).to.equal(s)
      expect(b.weight).to.equal(1.0)
    end)

    it("accepts reverse order (type dispatch)", function()
      local b = bind { s, g }
      expect(b.grader).to.equal(g)
      expect(b.scorer).to.equal(s)
    end)

    it("creates with grader only (default bool scorer)", function()
      local b = bind { g }
      expect(b.grader).to.equal(g)
      expect(b.scorer.name).to.equal("_bool")
    end)

    it("accepts weight override", function()
      local b = bind { g, s, weight = 0.5 }
      expect(b.weight).to.equal(0.5)
    end)

    it("creates with label syntax", function()
      local b = bind "accuracy" { g, s }
      expect(bind.is_binding(b)).to.equal(true)
    end)
  end)

  -- ============================================================
  -- Validation
  -- ============================================================

  describe("validation", function()
    it("rejects missing grader", function()
      h.assert_error_contains(function()
        bind { s }
      end, "GraderDef required")
    end)

    it("rejects multiple graders", function()
      h.assert_error_contains(function()
        bind { g, graders.contains }
      end, "multiple GraderDef")
    end)

    it("rejects negative weight", function()
      h.assert_error_contains(function()
        bind { g, weight = -1 }
      end, "weight must be non-negative")
    end)
  end)

  -- ============================================================
  -- Introspection
  -- ============================================================

  describe("introspection", function()
    it("key returns grader name", function()
      local b = bind { g }
      expect(bind.key(b)).to.equal("exact_match")
    end)

    it("is_binding detects bindings", function()
      expect(bind.is_binding(bind { g })).to.equal(true)
      expect(bind.is_binding({ grader = g })).to.equal(false)
    end)
  end)

  -- ============================================================
  -- Default bool scorer behavior
  -- ============================================================

  describe("default scorer", function()
    it("converts bool to score", function()
      local b = bind { g }
      expect(b.scorer.score(true)).to.equal(1.0)
      expect(b.scorer.score(false)).to.equal(0.0)
    end)

    it("clamps numbers to [0,1]", function()
      local b = bind { g }
      expect(b.scorer.score(0.5)).to.equal(0.5)
      expect(b.scorer.score(1.5)).to.equal(1.0)
    end)

    it("treats nil as 0", function()
      local b = bind { g }
      expect(b.scorer.score(nil)).to.equal(0.0)
    end)
  end)
end)
