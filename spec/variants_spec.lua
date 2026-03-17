local variants = require("evalframe.variants")
local h        = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
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
      expect(dim.dimension).to.equal("model")
      expect(#dim.entries).to.equal(2)
      expect(dim.entries[1].name).to.equal("gpt4")
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
      expect(dim.entries[1].name).to.equal("scale_1")
      expect(dim.entries[2].name).to.equal("scale_2")
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

      expect(#result).to.equal(4)

      -- Verify all combinations exist
      local names = {}
      for _, v in ipairs(result) do names[v.name] = true end
      expect(names["gpt4_cold"]).to.equal(true)
      expect(names["gpt4_hot"]).to.equal(true)
      expect(names["claude_cold"]).to.equal(true)
      expect(names["claude_hot"]).to.equal(true)
    end)

    it("merges base with dimension overrides", function()
      local result = variants.generate {
        base = { temperature = 0.7, max_tokens = 100 },

        variants.vary "model" {
          { model = "gpt-4", name = "gpt4" },
        },

        mode = "cross",
      }

      expect(#result).to.equal(1)
      expect(result[1].model).to.equal("gpt-4")
      expect(result[1].temperature).to.equal(0.7)  -- from base
      expect(result[1].max_tokens).to.equal(100)    -- from base
    end)

    it("dimension values override base values", function()
      local result = variants.generate {
        base = { temperature = 0.7 },

        variants.vary "temp" {
          { temperature = 0.0, name = "cold" },
        },

        mode = "cross",
      }

      expect(result[1].temperature).to.equal(0.0)  -- overridden
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
      expect(#result).to.equal(4)

      -- Verify merged values
      local found = false
      for _, v in ipairs(result) do
        if v.x == 2 and v.y == 20 and v.z == 100 then
          found = true
          expect(v.name).to.equal("a2_b2_c1")
        end
      end
      expect(found).to.equal(true)
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

      expect(#result).to.equal(4)
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

      expect(#result).to.equal(2)
      expect(result[1].name).to.equal("gpt4_cold")
      expect(result[1].model).to.equal("gpt-4")
      expect(result[1].temperature).to.equal(0.0)

      expect(result[2].name).to.equal("claude_hot")
      expect(result[2].model).to.equal("claude")
      expect(result[2].temperature).to.equal(1.0)
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

      expect(#result).to.equal(2)
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

      expect(#result).to.equal(2)
      expect(result[1].name).to.equal("gpt4")
      expect(result[1].shared).to.equal(true)
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

      expect(result[1].name).to.equal("alpha_beta")
    end)

    it("name does not collide with base keys", function()
      local result = variants.generate {
        base = { name = "should_be_overwritten" },

        variants.vary "a" { { x = 1, name = "v1" } },
      }

      expect(result[1].name).to.equal("v1")
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

      expect(base.model).to.equal(nil)
      expect(base.name).to.equal(nil)
    end)

    it("does not mutate entry tables when auto-generating names", function()
      local entries = {
        { model = "gpt-4" },
        { model = "claude" },
      }

      variants.generate {
        base = {},
        variants.vary "model" (entries),
      }

      -- entries should NOT have name fields injected
      expect(entries[1].name).to.equal(nil)
      expect(entries[2].name).to.equal(nil)
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
      expect(result[2].x).to.equal(2)  -- not affected
    end)
  end)
end)
