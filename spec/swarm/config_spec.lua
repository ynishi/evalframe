local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

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
      assert.is_true(sw.is_swarm_config(cfg))
      assert.equals(3, cfg.workers)
      assert.equals(20, cfg.max_ticks)
    end)

    it("applies defaults for optional fields", function()
      local cfg = sw.swarm {
        workers   = 1,
        max_ticks = 10,
      }
      assert.equals(1, cfg.managers)
      assert.is_nil(cfg.strategy)
    end)

    it("accepts all optional fields", function()
      local cfg = sw.swarm {
        workers         = 3,
        managers        = 2,
        max_ticks       = 20,
        tick_duration_ms = 10,
        strategy        = "ucb1",
        exploration     = true,
      }
      assert.equals(2, cfg.managers)
      assert.equals(10, cfg.tick_duration_ms)
      assert.equals("ucb1", cfg.strategy)
      assert.is_true(cfg.exploration)
    end)

    it("preserves arbitrary extra params", function()
      local cfg = sw.swarm {
        workers   = 1,
        max_ticks = 5,
        custom_field = "hello",
      }
      assert.equals("hello", cfg.custom_field)
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
  end)
end)
