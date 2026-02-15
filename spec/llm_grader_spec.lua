local llm_graders = require("evalframe.presets.llm_graders")
local grader      = require("evalframe.model.grader")
local case        = require("evalframe.model.case")
local mock        = require("evalframe.providers.mock")
local h           = require("spec.spec_helper")

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
      assert.is_true(grader.is_grader(judge))
      assert.truthy(judge.name:find("^llm_judge:"))
    end)

    it("extracts numeric rating from judge response", function()
      local judge = llm_graders.rubric("Rate accuracy 1-5", {
        provider = mock.static("4"),
      })
      local c = case { input = "What is 2+2?", expected = "4" }
      local val = judge.check({ text = "4" }, c)
      assert.equals(4, val)
    end)

    it("handles rating with surrounding text", function()
      local judge = llm_graders.rubric("Rate accuracy", {
        provider = mock.static("I rate this 3 out of 5"),
      })
      local c = case { input = "q" }
      local val = judge.check({ text = "answer" }, c)
      assert.equals(3, val)
    end)

    it("clamps to scale range", function()
      local judge = llm_graders.rubric("Rate", {
        provider = mock.static("99"),
        scale_max = 5,
      })
      local c = case { input = "q" }
      local val = judge.check({ text = "answer" }, c)
      assert.equals(5, val)
    end)

    it("returns error on non-numeric response", function()
      local judge = llm_graders.rubric("Rate", {
        provider = mock.static("I cannot rate this"),
      })
      local c = case { input = "q" }
      local val, err = judge.check({ text = "answer" }, c)
      assert.is_nil(val)
      assert.truthy(err:find("did not return a number"))
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
      assert.is_true(val)
    end)

    it("returns false for no", function()
      local judge = llm_graders.yes_no("Is this correct?", {
        provider = mock.static("No"),
      })
      local val = judge.check({ text = "5" }, case { input = "2+2?" })
      assert.is_false(val)
    end)

    it("handles case insensitivity", function()
      local judge = llm_graders.yes_no("Is this correct?", {
        provider = mock.static("YES"),
      })
      local val = judge.check({ text = "4" }, case { input = "2+2?" })
      assert.is_true(val)
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
      assert.equals(5, val)
    end)

    it("handles provider error", function()
      local judge = llm_graders.factuality({
        provider = function(_) return { text = "", error = "timeout" } end,
      })
      local c = case { input = "q", expected = "a" }
      local val, err = judge.check({ text = "x" }, c)
      assert.is_nil(val)
      assert.equals("timeout", err)
    end)
  end)
end)
