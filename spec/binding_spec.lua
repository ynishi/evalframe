local bind    = require("evalframe.model.binding")
local grader  = require("evalframe.model.grader")
local scorer  = require("evalframe.model.scorer")
local graders = require("evalframe.presets.graders")
local scorers = require("evalframe.presets.scorers")
local h       = require("spec.spec_helper")

describe("Binding", function()

  local g = graders.exact_match
  local s = scorers.linear_1_5

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates with grader + scorer", function()
      local b = bind { g, s }
      assert.is_true(bind.is_binding(b))
      assert.equals(g, b.grader)
      assert.equals(s, b.scorer)
      assert.equals(1.0, b.weight)
    end)

    it("accepts reverse order (type dispatch)", function()
      local b = bind { s, g }
      assert.equals(g, b.grader)
      assert.equals(s, b.scorer)
    end)

    it("creates with grader only (default bool scorer)", function()
      local b = bind { g }
      assert.equals(g, b.grader)
      assert.equals("_bool", b.scorer.name)
    end)

    it("accepts weight override", function()
      local b = bind { g, s, weight = 0.5 }
      assert.equals(0.5, b.weight)
    end)

    it("creates with label syntax", function()
      local b = bind "accuracy" { g, s }
      assert.is_true(bind.is_binding(b))
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
      assert.equals("exact_match", bind.key(b))
    end)

    it("is_binding detects bindings", function()
      assert.is_true(bind.is_binding(bind { g }))
      assert.is_false(bind.is_binding({ grader = g }))
    end)
  end)

  -- ============================================================
  -- Default bool scorer behavior
  -- ============================================================

  describe("default scorer", function()
    it("converts bool to score", function()
      local b = bind { g }
      assert.equals(1.0, b.scorer.score(true))
      assert.equals(0.0, b.scorer.score(false))
    end)

    it("clamps numbers to [0,1]", function()
      local b = bind { g }
      assert.equals(0.5, b.scorer.score(0.5))
      assert.equals(1.0, b.scorer.score(1.5))
    end)

    it("treats nil as 0", function()
      local b = bind { g }
      assert.equals(0.0, b.scorer.score(nil))
    end)
  end)
end)
