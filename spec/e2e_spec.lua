local ef = require("evalframe")
local h  = require("spec.spec_helper")

describe("E2E", function()

  -- ============================================================
  -- Full pipeline: mock provider → eval → report
  -- ============================================================

  describe("math eval pipeline", function()
    local provider = h.mock_provider({
      ["What is 2+2?"]   = "4",
      ["What is 3*3?"]   = "9",
      ["What is 10/3?"]  = "3.33",
      ["What is 0/0?"]   = "undefined",
    })

    it("runs complete eval with exact_match", function()
      local s = ef.suite "math" {
        provider = provider,
        ef.bind { ef.graders.exact_match },
        cases = {
          ef.case "add"  { input = "What is 2+2?",  expected = "4" },
          ef.case "mul"  { input = "What is 3*3?",  expected = "9" },
          ef.case "div"  { input = "What is 10/3?", expected = "3.33" },
        },
      }

      local report = s:run()
      assert.equals(3, report.aggregated.total)
      assert.equals(3, report.aggregated.passed)
      assert.equals(1.0, report.aggregated.pass_rate)
    end)

    it("detects failures", function()
      local s = ef.suite "math_fail" {
        provider = provider,
        ef.bind { ef.graders.exact_match },
        cases = {
          ef.case { input = "What is 2+2?",  expected = "4" },
          ef.case { input = "What is 0/0?",  expected = "NaN" },  -- will fail
        },
      }

      local report = s:run()
      assert.equals(2, report.aggregated.total)
      assert.equals(1, report.aggregated.passed)
      assert.equals(1, #report.failures)
    end)

    it("produces readable summary", function()
      local s = ef.suite "summary_test" {
        provider = provider,
        ef.bind { ef.graders.exact_match },
        cases = {
          ef.case { input = "What is 2+2?", expected = "4", tags = { "basic" } },
          ef.case { input = "What is 3*3?", expected = "9", tags = { "basic" } },
          ef.case { input = "What is 0/0?", expected = "NaN", tags = { "edge" } },
        },
      }

      local report = s:run()
      local text = report:summary()
      assert.truthy(text:find("Suite: summary_test"))
      assert.truthy(text:find("Pass: 2"))
      assert.truthy(text:find("Fail: 1"))
      assert.truthy(text:find("basic"))
      assert.truthy(text:find("edge"))
    end)
  end)

  -- ============================================================
  -- Multiple bindings (weighted grading)
  -- ============================================================

  describe("multi-binding eval", function()
    it("computes weighted score across bindings", function()
      local provider = h.static_provider("The answer is 4")

      local s = ef.suite "weighted" {
        provider = provider,
        ef.bind { ef.graders.contains,  weight = 0.7 },  -- "4" present → pass
        ef.bind { ef.graders.exact_match, weight = 0.3 }, -- not exact → fail
        cases = {
          ef.case { input = "2+2?", expected = "4" },
        },
      }

      local report = s:run()
      local result = report.results[1]

      -- contains passes (1.0 * 0.7), exact fails (0.0 * 0.3)
      -- weighted = 0.7 / 1.0 = 0.7
      assert.near(0.7, result.score, 0.01)
      assert.is_false(result.passed)  -- < 1.0
    end)
  end)

  -- ============================================================
  -- Grader + explicit scorer
  -- ============================================================

  describe("grader with scorer", function()
    it("uses linear scorer for rating-based grader", function()
      local rating_grader = ef.grader "rating" {
        check = function(resp, _case)
          -- Simulate: extract numeric rating from response
          return tonumber(resp.text:match("%d+")) or 0
        end
      }

      local provider = h.static_provider("Rating: 4 out of 5")

      local s = ef.suite "rating_test" {
        provider = provider,
        ef.bind { rating_grader, ef.scorers.linear_1_5 },
        cases = {
          ef.case { input = "Rate this" },
        },
      }

      local report = s:run()
      local result = report.results[1]
      -- rating=4, linear_1_5: (4-1)/(5-1) = 0.75
      assert.near(0.75, result.score, 0.01)
    end)
  end)

  -- ============================================================
  -- Cases built externally before Suite construction
  -- ============================================================

  describe("external case building", function()
    it("accepts cases array built outside Suite", function()
      local provider = h.static_provider("yes")

      local cases = {
        ef.case { input = "q1" },
        ef.case { input = "q2" },
      }

      local report = ef.suite "dynamic" {
        provider = provider,
        ef.bind { ef.graders.not_empty },
        cases = cases,
      }:run()

      assert.equals(2, report.aggregated.total)
      assert.equals(2, report.aggregated.passed)
    end)

    it("merges load_file results with inline cases", function()
      local provider = h.static_provider("yes")

      -- Simulate: cases from multiple sources merged before Suite
      local from_source_a = { ef.case { input = "a1" } }
      local from_source_b = { ef.case { input = "b1" }, ef.case { input = "b2" } }

      local all_cases = {}
      for _, c in ipairs(from_source_a) do all_cases[#all_cases + 1] = c end
      for _, c in ipairs(from_source_b) do all_cases[#all_cases + 1] = c end

      local report = ef.suite "merged" {
        provider = provider,
        ef.bind { ef.graders.not_empty },
        cases = all_cases,
      }:run()

      assert.equals(3, report.aggregated.total)
      assert.equals(3, report.aggregated.passed)
    end)
  end)

  -- ============================================================
  -- Error handling
  -- ============================================================

  describe("error handling", function()
    it("handles provider errors gracefully", function()
      local bad_provider = function(_input) error("connection refused") end

      local s = ef.suite "error_test" {
        provider = bad_provider,
        ef.bind { ef.graders.not_empty },
        cases = {
          ef.case { input = "test" },
        },
      }

      -- Should not crash
      local report = s:run()
      assert.equals(1, report.aggregated.total)
      assert.equals(0, report.aggregated.passed)
    end)

    it("rejects suite with no cases on run", function()
      local s = ef.suite "empty" {
        provider = function() return "" end,
        ef.bind { ef.graders.not_empty },
        cases = {},
      }
      h.assert_error_contains(function()
        s:run()
      end, "no cases")
    end)
  end)

  -- ============================================================
  -- Type mismatch warning
  -- ============================================================

  describe("type mismatch warning", function()
    it("warns when grader returns string but scorer expects number", function()
      local string_grader = ef.grader "string_returner" {
        check = function(_resp, _case)
          return "some text"
        end
      }

      local s = ef.suite "type_warn" {
        provider = h.static_provider("hello"),
        ef.bind { string_grader, ef.scorers.linear_1_5 },
        cases = {
          ef.case { input = "q" },
        },
      }

      local report = s:run()
      local grade = report.results[1].grades[1]
      assert.equals(0.0, grade.score)
      assert.truthy(grade.warning)
      assert.truthy(grade.warning:find("type mismatch"))
    end)

    it("truncates multi-byte input label at character boundary", function()
      -- 50 chars of 3-byte UTF-8 = 150 bytes, exceeds 40-byte limit
      local long_input = string.rep("\xe3\x81\x82", 50)  -- "あ" * 50
      local s = ef.suite "utf8_test" {
        provider = h.static_provider("x"),
        ef.bind { ef.graders.not_empty },
        cases = {
          ef.case { input = long_input },
        },
      }
      local report = s:run()
      local text = report.format_result(report.results[1])
      -- Label should be 13 complete "あ" (39 bytes) + "..."
      -- 13 chars * 3 bytes = 39 bytes (largest complete char boundary <= 40)
      local expected_label = string.rep("\xe3\x81\x82", 13) .. "..."
      assert.truthy(text:find(expected_label, 1, true))
    end)

    it("does not warn on normal bool grader", function()
      local s = ef.suite "no_warn" {
        provider = h.static_provider("4"),
        ef.bind { ef.graders.exact_match },
        cases = {
          ef.case { input = "q", expected = "4" },
        },
      }

      local report = s:run()
      local grade = report.results[1].grades[1]
      assert.is_nil(grade.warning)
    end)
  end)
end)
