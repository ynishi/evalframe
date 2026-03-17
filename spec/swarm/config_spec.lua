local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("sw.swarm", function()

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates swarm config with required fields", function()
      local cfg = sw.swarm {
        workers   = 3,
        max_ticks = 20,
      }
      expect(sw.is_swarm_config(cfg)).to.equal(true)
      expect(cfg.workers).to.equal(3)
      expect(cfg.max_ticks).to.equal(20)
    end)

    it("applies defaults for optional fields", function()
      local cfg = sw.swarm {
        workers   = 1,
        max_ticks = 10,
      }
      expect(cfg.managers).to.equal(1)
      expect(cfg.strategy).to.equal(nil)
    end)

    it("accepts all known optional fields", function()
      local cfg = sw.swarm {
        workers   = 3,
        managers  = 2,
        max_ticks = 20,
        strategy  = "ucb1",
      }
      expect(cfg.managers).to.equal(2)
      expect(cfg.strategy).to.equal("ucb1")
    end)
  end)

  -- ============================================================
  -- Strict schema: unknown fields rejected
  -- ============================================================

  describe("strict schema", function()
    it("rejects unknown fields", function()
      h.assert_error_contains(function()
        sw.swarm {
          workers   = 1,
          max_ticks = 5,
          custom_field = "hello",
        }
      end, "unknown field 'custom_field'")
    end)

    it("catches typos in field names", function()
      h.assert_error_contains(function()
        sw.swarm {
          workers   = 3,
          max_ticks = 20,
          strategyy = "ucb1",
        }
      end, "unknown field 'strategyy'")
    end)
  end)

  -- ============================================================
  -- Validation
  -- ============================================================

  describe("validation", function()
    it("rejects non-table spec", function()
      h.assert_error_contains(function()
        sw.swarm "bad"
      end, "spec must be a table")
    end)

    it("rejects missing workers", function()
      h.assert_error_contains(function()
        sw.swarm { max_ticks = 10 }
      end, "workers is required")
    end)

    it("rejects missing max_ticks", function()
      h.assert_error_contains(function()
        sw.swarm { workers = 3 }
      end, "max_ticks is required")
    end)

    it("rejects non-positive workers", function()
      h.assert_error_contains(function()
        sw.swarm { workers = 0, max_ticks = 10 }
      end, "workers must be a positive integer")
    end)

    it("rejects non-positive max_ticks", function()
      h.assert_error_contains(function()
        sw.swarm { workers = 1, max_ticks = -1 }
      end, "max_ticks must be a positive integer")
    end)

    it("rejects non-integer workers", function()
      h.assert_error_contains(function()
        sw.swarm { workers = 2.5, max_ticks = 10 }
      end, "workers must be a positive integer")
    end)

    it("rejects non-string strategy", function()
      h.assert_error_contains(function()
        sw.swarm { workers = 1, max_ticks = 10, strategy = 42 }
      end, "strategy must be string")
    end)

    it("rejects non-positive managers", function()
      h.assert_error_contains(function()
        sw.swarm { workers = 1, max_ticks = 10, managers = 0 }
      end, "managers must be a positive integer")
    end)
  end)
end)
