local variants = require("evalframe.variants")
local h        = require("spec.spec_helper")

describe("variants", function()

  -- ============================================================
  -- vary: dimension declaration
  -- ============================================================

  describe("vary", function()
    it("creates a dimension with name and entries", function()
      local dim = variants.vary "model" {
        { model = "gpt-4",  name = "gpt4" },
        { model = "claude", name = "claude" },
      }
      assert.equals("model", dim.dimension)
      assert.equals(2, #dim.entries)
      assert.equals("gpt4", dim.entries[1].name)
    end)

    it("rejects empty entries", function()
      h.assert_error_contains(function()
        variants.vary "empty" {}
      end, "at least 1 entry")
    end)

    it("rejects non-string dimension name", function()
      h.assert_error_contains(function()
        variants.vary(42)
      end, "name must be string")
    end)

    it("auto-generates name from dimension + index when name omitted", function()
      local dim = variants.vary "scale" {
        { workers = 1 },
        { workers = 3 },
      }
      assert.equals("scale_1", dim.entries[1].name)
      assert.equals("scale_2", dim.entries[2].name)
    end)
  end)

  -- ============================================================
  -- generate: cross mode (default)
  -- ============================================================

  describe("cross mode", function()
    it("produces cartesian product of two dimensions", function()
      local result = variants.generate {
        base = { temperature = 0.7 },

        variants.vary "model" {
          { model = "gpt-4",  name = "gpt4" },
          { model = "claude", name = "claude" },
        },

        variants.vary "temp" {
          { temperature = 0.0, name = "cold" },
          { temperature = 1.0, name = "hot" },
        },

        mode = "cross",
      }

      assert.equals(4, #result)

      -- Verify all combinations exist
      local names = {}
      for _, v in ipairs(result) do names[v.name] = true end
      assert.is_true(names["gpt4_cold"])
      assert.is_true(names["gpt4_hot"])
      assert.is_true(names["claude_cold"])
      assert.is_true(names["claude_hot"])
    end)

    it("merges base with dimension overrides", function()
      local result = variants.generate {
        base = { temperature = 0.7, max_tokens = 100 },

        variants.vary "model" {
          { model = "gpt-4", name = "gpt4" },
        },

        mode = "cross",
      }

      assert.equals(1, #result)
      assert.equals("gpt-4", result[1].model)
      assert.equals(0.7, result[1].temperature)  -- from base
      assert.equals(100, result[1].max_tokens)    -- from base
    end)

    it("dimension values override base values", function()
      local result = variants.generate {
        base = { temperature = 0.7 },

        variants.vary "temp" {
          { temperature = 0.0, name = "cold" },
        },

        mode = "cross",
      }

      assert.equals(0.0, result[1].temperature)  -- overridden
    end)

    it("cross product with three dimensions", function()
      local result = variants.generate {
        base = {},

        variants.vary "a" {
          { x = 1, name = "a1" },
          { x = 2, name = "a2" },
        },

        variants.vary "b" {
          { y = 10, name = "b1" },
          { y = 20, name = "b2" },
        },

        variants.vary "c" {
          { z = 100, name = "c1" },
        },

        mode = "cross",
      }

      -- 2 x 2 x 1 = 4
      assert.equals(4, #result)

      -- Verify merged values
      local found = false
      for _, v in ipairs(result) do
        if v.x == 2 and v.y == 20 and v.z == 100 then
          found = true
          assert.equals("a2_b2_c1", v.name)
        end
      end
      assert.is_true(found)
    end)

    it("defaults to cross mode when mode omitted", function()
      local result = variants.generate {
        base = {},

        variants.vary "a" {
          { x = 1, name = "x1" },
          { x = 2, name = "x2" },
        },

        variants.vary "b" {
          { y = 1, name = "y1" },
          { y = 2, name = "y2" },
        },
      }

      assert.equals(4, #result)
    end)
  end)

  -- ============================================================
  -- generate: zip mode
  -- ============================================================

  describe("zip mode", function()
    it("produces 1:1 pairing", function()
      local result = variants.generate {
        base = {},

        variants.vary "model" {
          { model = "gpt-4",  name = "gpt4" },
          { model = "claude", name = "claude" },
        },

        variants.vary "temp" {
          { temperature = 0.0, name = "cold" },
          { temperature = 1.0, name = "hot" },
        },

        mode = "zip",
      }

      assert.equals(2, #result)
      assert.equals("gpt4_cold", result[1].name)
      assert.equals("gpt-4", result[1].model)
      assert.equals(0.0, result[1].temperature)

      assert.equals("claude_hot", result[2].name)
      assert.equals("claude", result[2].model)
      assert.equals(1.0, result[2].temperature)
    end)

    it("truncates to shortest dimension", function()
      local result = variants.generate {
        base = {},

        variants.vary "a" {
          { x = 1, name = "a1" },
          { x = 2, name = "a2" },
          { x = 3, name = "a3" },
        },

        variants.vary "b" {
          { y = 10, name = "b1" },
          { y = 20, name = "b2" },
        },

        mode = "zip",
      }

      assert.equals(2, #result)
    end)
  end)

  -- ============================================================
  -- generate: single dimension
  -- ============================================================

  describe("single dimension", function()
    it("works with just one vary", function()
      local result = variants.generate {
        base = { shared = true },

        variants.vary "model" {
          { model = "gpt-4",  name = "gpt4" },
          { model = "claude", name = "claude" },
        },
      }

      assert.equals(2, #result)
      assert.equals("gpt4", result[1].name)
      assert.is_true(result[1].shared)
    end)
  end)

  -- ============================================================
  -- generate: validation
  -- ============================================================

  describe("validation", function()
    it("rejects non-table spec", function()
      h.assert_error_contains(function()
        variants.generate("bad")
      end, "spec must be a table")
    end)

    it("rejects spec without any vary dimensions", function()
      h.assert_error_contains(function()
        variants.generate { base = {} }
      end, "at least one vary dimension")
    end)

    it("rejects unknown mode", function()
      h.assert_error_contains(function()
        variants.generate {
          base = {},
          variants.vary "a" { { x = 1, name = "a1" } },
          mode = "shuffle",
        }
      end, "mode must be 'cross' or 'zip'")
    end)
  end)

  -- ============================================================
  -- name field is preserved in variant (not just meta)
  -- ============================================================

  describe("name generation", function()
    it("joins dimension entry names with underscore", function()
      local result = variants.generate {
        base = {},

        variants.vary "a" { { x = 1, name = "alpha" } },
        variants.vary "b" { { y = 2, name = "beta" } },

        mode = "cross",
      }

      assert.equals("alpha_beta", result[1].name)
    end)

    it("name does not collide with base keys", function()
      local result = variants.generate {
        base = { name = "should_be_overwritten" },

        variants.vary "a" { { x = 1, name = "v1" } },
      }

      assert.equals("v1", result[1].name)
    end)
  end)

  -- ============================================================
  -- immutability: base is not mutated
  -- ============================================================

  describe("immutability", function()
    it("does not mutate the base table", function()
      local base = { temperature = 0.7 }

      variants.generate {
        base = base,
        variants.vary "model" {
          { model = "gpt-4", name = "gpt4" },
        },
      }

      assert.is_nil(base.model)
      assert.is_nil(base.name)
    end)

    it("variants are independent tables", function()
      local result = variants.generate {
        base = { items = {} },
        variants.vary "a" {
          { x = 1, name = "v1" },
          { x = 2, name = "v2" },
        },
      }

      result[1].x = 999
      assert.equals(2, result[2].x)  -- not affected
    end)
  end)
end)
