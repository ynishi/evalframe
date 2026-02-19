local grader  = require("evalframe.model.grader")
local graders = require("evalframe.presets.graders")
local case    = require("evalframe.model.case")
local h       = require("spec.spec_helper")

describe("Grader", function()

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates from name + check function", function()
      local g = grader "my_grader" {
        check = function(resp, c) return resp.text == "ok" end
      }
      assert.is_true(grader.is_grader(g))
      assert.equals("my_grader", g.name)
    end)

    it("rejects missing check", function()
      h.assert_error_contains(function()
        grader "bad" { }
      end, "'check' must be function")
    end)

    it("rejects non-string name", function()
      h.assert_error_contains(function()
        grader(42)
      end, "name must be string")
    end)
  end)

  -- ============================================================
  -- Preset graders
  -- ============================================================

  describe("presets", function()
    local c = case { input = "q", expected = "hello world" }

    describe("exact_match", function()
      it("passes on exact match", function()
        local val = graders.exact_match.check({ text = "hello world" }, c)
        assert.is_true(val)
      end)

      it("fails on partial match", function()
        local val = graders.exact_match.check({ text = "hello" }, c)
        assert.is_false(val)
      end)
    end)

    describe("contains", function()
      it("passes when text contains expected", function()
        local val = graders.contains.check({ text = "say hello world now" }, c)
        assert.is_true(val)
      end)

      it("fails when text does not contain expected", function()
        local val = graders.contains.check({ text = "goodbye" }, c)
        assert.is_false(val)
      end)
    end)

    describe("starts_with", function()
      it("passes when text starts with expected", function()
        local val = graders.starts_with.check({ text = "hello world!" }, c)
        assert.is_true(val)
      end)

      it("fails on wrong prefix", function()
        local val = graders.starts_with.check({ text = "world hello" }, c)
        assert.is_false(val)
      end)
    end)

    describe("not_empty", function()
      it("passes for non-empty text", function()
        local val = graders.not_empty.check({ text = "x" }, c)
        assert.is_true(val)
      end)

      it("fails for empty text", function()
        local val = graders.not_empty.check({ text = "" }, c)
        assert.is_false(val)
      end)
    end)

    describe("length", function()
      it("returns text length", function()
        local val = graders.length.check({ text = "hello" }, c)
        assert.equals(5, val)
      end)
    end)

    describe("regex", function()
      it("matches Lua pattern from context", function()
        local rc = case { input = "q", context = { pattern = "%d+" } }
        local val = graders.regex.check({ text = "answer is 42" }, rc)
        assert.is_true(val)
      end)

      it("fails when pattern doesn't match", function()
        local rc = case { input = "q", context = { pattern = "%d+" } }
        local val = graders.regex.check({ text = "no numbers" }, rc)
        assert.is_false(val)
      end)

      it("falls back to expected[1] as pattern", function()
        local rc = case { input = "q", expected = "%d+" }
        local val = graders.regex.check({ text = "answer is 42" }, rc)
        assert.is_true(val)
      end)

      it("context.pattern takes precedence over expected[1]", function()
        local rc = case { input = "q", expected = "NOMATCH", context = { pattern = "%d+" } }
        local val = graders.regex.check({ text = "answer is 42" }, rc)
        assert.is_true(val)  -- context.pattern wins, not expected[1]
      end)
    end)

    describe("latency", function()
      it("returns latency_ms when present", function()
        local val = graders.latency.check({ text = "ok", latency_ms = 150 }, c)
        assert.equals(150, val)
      end)

      it("returns nil when latency_ms is missing", function()
        local val = graders.latency.check({ text = "ok" }, c)
        assert.is_nil(val)
      end)
    end)
  end)

  -- ============================================================
  -- Combinators
  -- ============================================================

  describe("combinators", function()
    local g_yes = grader "yes" { check = function() return true end }
    local g_no  = grader "no"  { check = function() return false end }

    it("all passes when all pass", function()
      local combined = grader.all(g_yes, g_yes)
      assert.is_true(grader.is_grader(combined))
      local val = combined.check({ text = "" }, case { input = "q" })
      assert.is_true(val)
    end)

    it("all fails when any fails", function()
      local combined = grader.all(g_yes, g_no)
      local val = combined.check({ text = "" }, case { input = "q" })
      assert.is_false(val)
    end)

    it("any passes when at least one passes", function()
      local combined = grader.any(g_no, g_yes)
      local val = combined.check({ text = "" }, case { input = "q" })
      assert.is_true(val)
    end)

    it("any fails when all fail", function()
      local combined = grader.any(g_no, g_no)
      local val = combined.check({ text = "" }, case { input = "q" })
      assert.is_false(val)
    end)

    it("all returns 0 (not true) when numeric graders all return 0", function()
      local g_zero = grader "zero" { check = function() return 0 end }
      local combined = grader.all(g_zero, g_zero)
      local val = combined.check({ text = "" }, case { input = "q" })
      assert.equals(0, val)
    end)

    it("all returns minimum for mixed numeric graders", function()
      local g_low  = grader "low"  { check = function() return 2 end }
      local g_high = grader "high" { check = function() return 5 end }
      local combined = grader.all(g_low, g_high)
      local val = combined.check({ text = "" }, case { input = "q" })
      assert.equals(2, val)
    end)
  end)

  -- ============================================================
  -- Composed presets (Combinator consumers)
  -- ============================================================

  describe("composed presets", function()
    it("valid_json_response passes for non-empty valid JSON", function()
      local c = case { input = "q" }
      local val = graders.valid_json_response.check({ text = '{"ok":true}' }, c)
      assert.is_true(val)
    end)

    it("valid_json_response fails for empty text", function()
      local c = case { input = "q" }
      local val = graders.valid_json_response.check({ text = "" }, c)
      assert.is_false(val)
    end)

    it("valid_json_response fails for invalid JSON", function()
      local c = case { input = "q" }
      local val = graders.valid_json_response.check({ text = "not json" }, c)
      assert.is_false(val)
    end)

    it("flexible_match passes on exact match", function()
      local c = case { input = "q", expected = "hello" }
      local val = graders.flexible_match.check({ text = "hello" }, c)
      assert.is_true(val)
    end)

    it("flexible_match passes on contains", function()
      local c = case { input = "q", expected = "hello" }
      local val = graders.flexible_match.check({ text = "say hello world" }, c)
      assert.is_true(val)
    end)

    it("flexible_match fails when neither matches", function()
      local c = case { input = "q", expected = "hello" }
      local val = graders.flexible_match.check({ text = "goodbye" }, c)
      assert.is_false(val)
    end)
  end)

  -- ============================================================
  -- Safe check (error handling)
  -- ============================================================

  describe("safe check", function()
    it("returns nil + error message on exception", function()
      local g = grader "crasher" {
        check = function() error("boom") end
      }
      local val, err = g.check({ text = "" }, case { input = "q" })
      assert.is_nil(val)
      assert.truthy(err:find("boom", 1, true))
    end)
  end)
end)
