local report = require("evalframe.eval.report")
local stats  = require("evalframe.eval.stats")

describe("Report", function()

  -- ============================================================
  -- summary formatting
  -- ============================================================

  describe("summary", function()
    it("includes suite name when provided", function()
      local agg = stats.aggregate({})
      local text = report.summary(agg, { name = "test_suite" })
      assert.truthy(text:find("Suite: test_suite", 1, true))
    end)

    it("omits suite name when not provided", function()
      local agg = stats.aggregate({})
      local text = report.summary(agg)
      assert.falsy(text:find("Suite:", 1, true))
    end)

    it("shows pass@1 for any result set", function()
      local results = {
        { score = 1.0, passed = true, case = { tags = {} } },
      }
      local agg = stats.aggregate(results)
      local text = report.summary(agg)
      assert.truthy(text:find("pass@1:", 1, true))
    end)

    it("shows pass@5 when n >= 5", function()
      local results = {}
      for i = 1, 5 do
        results[i] = { score = 1.0, passed = true, case = { tags = {} } }
      end
      local agg = stats.aggregate(results)
      local text = report.summary(agg)
      assert.truthy(text:find("pass@5:", 1, true))
    end)

    it("omits pass@5 when n < 5", function()
      local results = {
        { score = 1.0, passed = true, case = { tags = {} } },
      }
      local agg = stats.aggregate(results)
      local text = report.summary(agg)
      assert.falsy(text:find("pass@5:", 1, true))
    end)

    it("shows Mean and CI", function()
      local results = {
        { score = 0.8, passed = false, case = { tags = {} } },
        { score = 1.0, passed = true,  case = { tags = {} } },
      }
      local agg = stats.aggregate(results)
      local text = report.summary(agg)
      assert.truthy(text:find("Mean:", 1, true))
      assert.truthy(text:find("95%% CI:"))
    end)

    it("shows by_tag section", function()
      local results = {
        { score = 1.0, passed = true, case = { tags = { "alpha" } } },
        { score = 0.0, passed = false, case = { tags = { "beta" } } },
      }
      local agg = stats.aggregate(results)
      local text = report.summary(agg)
      assert.truthy(text:find("By tag:", 1, true))
      assert.truthy(text:find("alpha", 1, true))
      assert.truthy(text:find("beta", 1, true))
    end)

    it("sorts tags alphabetically", function()
      local results = {
        { score = 1.0, passed = true, case = { tags = { "zebra" } } },
        { score = 1.0, passed = true, case = { tags = { "apple" } } },
      }
      local agg = stats.aggregate(results)
      local text = report.summary(agg)
      local apple_pos = text:find("apple", 1, true)
      local zebra_pos = text:find("zebra", 1, true)
      assert.truthy(apple_pos < zebra_pos)
    end)
  end)

  -- ============================================================
  -- failures
  -- ============================================================

  describe("failures", function()
    it("returns empty for all-pass results", function()
      local results = {
        { passed = true },
        { passed = true },
      }
      assert.equals(0, #report.failures(results))
    end)

    it("extracts only failed results", function()
      local results = {
        { passed = true },
        { passed = false },
        { passed = true },
        { passed = false },
      }
      assert.equals(2, #report.failures(results))
    end)
  end)

  -- ============================================================
  -- format_result
  -- ============================================================

  describe("format_result", function()
    it("shows PASS for passing result", function()
      local r = {
        passed = true,
        score = 1.0,
        case = { name = "test1", input = "q", tags = {} },
        response = { text = "a" },
        grades = { { grader = "exact_match", score = 1.0, grade = true, weight = 1.0 } },
      }
      local text = report.format_result(r)
      assert.truthy(text:find("[PASS]", 1, true))
    end)

    it("shows FAIL for failing result", function()
      local r = {
        passed = false,
        score = 0.0,
        case = { name = "test2", input = "q", tags = {} },
        response = { text = "" },
        grades = { { grader = "exact_match", score = 0.0, grade = false, weight = 1.0 } },
      }
      local text = report.format_result(r)
      assert.truthy(text:find("[FAIL]", 1, true))
    end)

    it("uses case name as label when present", function()
      local r = {
        passed = true,
        score = 1.0,
        case = { name = "my_case", input = "long input text here", tags = {} },
        response = { text = "a" },
        grades = {},
      }
      local text = report.format_result(r)
      assert.truthy(text:find("my_case", 1, true))
    end)

    it("shows error in grade detail", function()
      local r = {
        passed = false,
        score = 0.0,
        case = { name = "", input = "q", tags = {} },
        response = { text = "" },
        grades = { { grader = "bad", score = 0.0, grade = nil, weight = 1.0, error = "boom" } },
      }
      local text = report.format_result(r)
      assert.truthy(text:find("err=boom", 1, true))
    end)

    it("shows warning in grade detail", function()
      local r = {
        passed = false,
        score = 0.0,
        case = { name = "", input = "q", tags = {} },
        response = { text = "" },
        grades = { { grader = "g", score = 0.0, grade = "x", weight = 1.0, warning = "type mismatch" } },
      }
      local text = report.format_result(r)
      assert.truthy(text:find("WARN=type mismatch", 1, true))
    end)
  end)
end)
