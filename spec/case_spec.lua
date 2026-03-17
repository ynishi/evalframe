local case = require("evalframe.model.case")
local h    = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("Case", function()

  -- ============================================================
  -- Construction: normal
  -- ============================================================

  describe("construction", function()
    it("creates from minimal spec", function()
      local c = case { input = "What is 2+2?" }
      expect(case.is_case(c)).to.equal(true)
      expect(c.input).to.equal("What is 2+2?")
      expect(c.name).to.equal("")
      expect(c.expected).to.equal(nil)
    end)

    it("creates with all fields", function()
      local c = case {
        name     = "math_basic",
        input    = "What is 2+2?",
        expected = "4",
        context  = { domain = "math" },
        tags     = { "math", "basic" },
      }
      expect(c.name).to.equal("math_basic")
      expect(c.expected).to.equal({ "4" })  -- normalized to list
      expect(c.context.domain).to.equal("math")
      expect(c.tags).to.equal({ "math", "basic" })
    end)

    it("normalizes string expected to list", function()
      local c = case { input = "q", expected = "answer" }
      expect(c.expected).to.equal({ "answer" })
    end)

    it("accepts list of expected values", function()
      local c = case { input = "q", expected = { "a", "b" } }
      expect(c.expected).to.equal({ "a", "b" })
    end)

    it("accepts nil expected (open-ended)", function()
      local c = case { input = "q" }
      expect(c.expected).to.equal(nil)
    end)
  end)

  -- ============================================================
  -- DSL shorthand: case "name" { ... }
  -- ============================================================

  describe("named DSL syntax", function()
    it("creates with name as first arg", function()
      local c = case "my_test" { input = "hello" }
      expect(c.name).to.equal("my_test")
      expect(c.input).to.equal("hello")
    end)
  end)

  -- ============================================================
  -- Validation: errors
  -- ============================================================

  describe("validation", function()
    it("rejects missing input", function()
      h.assert_error_contains(function()
        case { name = "bad" }
      end, "'input' is required")
    end)

    it("rejects non-string input", function()
      h.assert_error_contains(function()
        case { input = 42 }
      end, "'input' must be string")
    end)

    it("rejects non-table argument", function()
      h.assert_error_contains(function()
        case(42)
      end, "expected table or string")
    end)

    it("rejects non-string expected list items", function()
      h.assert_error_contains(function()
        case { input = "q", expected = { 1, 2 } }
      end, "expected[1] must be string")
    end)
  end)

  -- ============================================================
  -- Immutability
  -- ============================================================

  describe("immutability", function()
    it("rejects field assignment after construction", function()
      local c = case { input = "q", expected = "a" }
      h.assert_error_contains(function()
        c.input = "changed"
      end, "Case is immutable")
    end)

    it("rejects new field assignment", function()
      local c = case { input = "q" }
      h.assert_error_contains(function()
        c.extra = "nope"
      end, "Case is immutable")
    end)

    it("defensive-copies expected (caller mutation does not affect case)", function()
      local exp = { "a", "b" }
      local c = case { input = "q", expected = exp }
      exp[1] = "CHANGED"
      expect(c.expected[1]).to.equal("a")
    end)

    it("defensive-copies tags (caller mutation does not affect case)", function()
      local tags = { "math" }
      local c = case { input = "q", tags = tags }
      tags[1] = "CHANGED"
      expect(c.tags[1]).to.equal("math")
    end)

    it("defensive-copies context (caller mutation does not affect case)", function()
      local ctx = { key = "val" }
      local c = case { input = "q", context = ctx }
      ctx.key = "CHANGED"
      expect(c.context.key).to.equal("val")
    end)
  end)

  -- ============================================================
  -- Introspection
  -- ============================================================

  describe("introspection", function()
    it("is_case returns true for Case", function()
      local c = case { input = "q" }
      expect(case.is_case(c)).to.equal(true)
    end)

    it("is_case returns false for plain table", function()
      expect(case.is_case({ input = "q" })).to.equal(false)
    end)

    it("has_tag checks tag presence", function()
      local c = case { input = "q", tags = { "math", "easy" } }
      expect(case.has_tag(c, "math")).to.equal(true)
      expect(case.has_tag(c, "hard")).to.equal(false)
    end)
  end)
end)
