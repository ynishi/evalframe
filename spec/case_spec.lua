local case = require("evalframe.model.case")
local h    = require("spec.spec_helper")

describe("Case", function()

  -- ============================================================
  -- Construction: normal
  -- ============================================================

  describe("construction", function()
    it("creates from minimal spec", function()
      local c = case { input = "What is 2+2?" }
      assert.is_true(case.is_case(c))
      assert.equals("What is 2+2?", c.input)
      assert.equals("", c.name)
      assert.is_nil(c.expected)
    end)

    it("creates with all fields", function()
      local c = case {
        name     = "math_basic",
        input    = "What is 2+2?",
        expected = "4",
        context  = { domain = "math" },
        tags     = { "math", "basic" },
      }
      assert.equals("math_basic", c.name)
      assert.same({ "4" }, c.expected)  -- normalized to list
      assert.equals("math", c.context.domain)
      assert.same({ "math", "basic" }, c.tags)
    end)

    it("normalizes string expected to list", function()
      local c = case { input = "q", expected = "answer" }
      assert.same({ "answer" }, c.expected)
    end)

    it("accepts list of expected values", function()
      local c = case { input = "q", expected = { "a", "b" } }
      assert.same({ "a", "b" }, c.expected)
    end)

    it("accepts nil expected (open-ended)", function()
      local c = case { input = "q" }
      assert.is_nil(c.expected)
    end)
  end)

  -- ============================================================
  -- DSL shorthand: case "name" { ... }
  -- ============================================================

  describe("named DSL syntax", function()
    it("creates with name as first arg", function()
      local c = case "my_test" { input = "hello" }
      assert.equals("my_test", c.name)
      assert.equals("hello", c.input)
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
  end)

  -- ============================================================
  -- Introspection
  -- ============================================================

  describe("introspection", function()
    it("is_case returns true for Case", function()
      local c = case { input = "q" }
      assert.is_true(case.is_case(c))
    end)

    it("is_case returns false for plain table", function()
      assert.is_false(case.is_case({ input = "q" }))
    end)

    it("has_tag checks tag presence", function()
      local c = case { input = "q", tags = { "math", "easy" } }
      assert.is_true(case.has_tag(c, "math"))
      assert.is_false(case.has_tag(c, "hard"))
    end)
  end)
end)
