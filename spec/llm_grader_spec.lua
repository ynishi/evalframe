local llm_graders = require("evalframe.presets.llm_graders")
local grader      = require("evalframe.model.grader")
local case        = require("evalframe.model.case")
local mock        = require("evalframe.providers.mock")
local h           = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("LLM Graders (Tier 2)", function()

  -- ============================================================
  -- Provider required
  -- ============================================================

  describe("provider required", function()
    it("rubric errors without provider", function()
      h.assert_error_contains(function()
        llm_graders.rubric("Rate accuracy")
      end, "'provider' is required")
    end)

    it("yes_no errors without provider", function()
      h.assert_error_contains(function()
        llm_graders.yes_no("Is this correct?")
      end, "'provider' is required")
    end)

    it("factuality errors without provider", function()
      h.assert_error_contains(function()
        llm_graders.factuality()
      end, "'provider' is required")
    end)

    it("rejects non-function provider", function()
      h.assert_error_contains(function()
        llm_graders.rubric("Rate", { provider = "not a function" })
      end, "'provider' must be function")
    end)
  end)

  -- ============================================================
  -- Rubric judge
  -- ============================================================

  describe("rubric", function()
    it("creates a valid grader", function()
      local judge = llm_graders.rubric("Rate accuracy", {
        provider = mock.static("4"),
      })
      expect(grader.is_grader(judge)).to.equal(true)
      expect(judge.name:find("^llm_judge:")).to.be.truthy()
    end)

    it("extracts numeric rating from judge response", function()
      local judge = llm_graders.rubric("Rate accuracy 1-5", {
        provider = mock.static("4"),
      })
      local c = case { input = "What is 2+2?", expected = "4" }
      local val = judge.check({ text = "4" }, c)
      expect(val).to.equal(4)
    end)

    it("handles rating with surrounding text", function()
      local judge = llm_graders.rubric("Rate accuracy", {
        provider = mock.static("I rate this 3 out of 5"),
      })
      local c = case { input = "q" }
      local val = judge.check({ text = "answer" }, c)
      expect(val).to.equal(3)
    end)

    it("clamps to scale range", function()
      local judge = llm_graders.rubric("Rate", {
        provider = mock.static("99"),
        scale_max = 5,
      })
      local c = case { input = "q" }
      local val = judge.check({ text = "answer" }, c)
      expect(val).to.equal(5)
    end)

    it("returns error on non-numeric response", function()
      local judge = llm_graders.rubric("Rate", {
        provider = mock.static("I cannot rate this"),
      })
      local c = case { input = "q" }
      local val, err = judge.check({ text = "answer" }, c)
      expect(val).to.equal(nil)
      expect(err:find("did not return a number")).to.be.truthy()
    end)
  end)

  -- ============================================================
  -- Yes/No judge
  -- ============================================================

  describe("yes_no", function()
    it("returns true for yes", function()
      local judge = llm_graders.yes_no("Is this correct?", {
        provider = mock.static("Yes"),
      })
      local val = judge.check({ text = "4" }, case { input = "2+2?" })
      expect(val).to.equal(true)
    end)

    it("returns false for no", function()
      local judge = llm_graders.yes_no("Is this correct?", {
        provider = mock.static("No"),
      })
      local val = judge.check({ text = "5" }, case { input = "2+2?" })
      expect(val).to.equal(false)
    end)

    it("handles case insensitivity", function()
      local judge = llm_graders.yes_no("Is this correct?", {
        provider = mock.static("YES"),
      })
      local val = judge.check({ text = "4" }, case { input = "2+2?" })
      expect(val).to.equal(true)
    end)
  end)

  -- ============================================================
  -- Factuality judge
  -- ============================================================

  describe("factuality", function()
    it("returns numeric rating", function()
      local judge = llm_graders.factuality({
        provider = mock.static("5"),
      })
      local c = case { input = "Capital of Japan?", expected = "Tokyo" }
      local val = judge.check({ text = "Tokyo" }, c)
      expect(val).to.equal(5)
    end)

    it("handles provider error", function()
      local judge = llm_graders.factuality({
        provider = function(_) return { text = "", error = "timeout" } end,
      })
      local c = case { input = "q", expected = "a" }
      local val, err = judge.check({ text = "x" }, c)
      expect(val).to.equal(nil)
      expect(err).to.equal("timeout")
    end)
  end)
end)
