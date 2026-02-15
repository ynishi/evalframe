local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

describe("sw.env", function()

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates environment declaration with name and params", function()
      local env = sw.env "troubleshooting" {
        scenario = "memory_leak",
        services = { "user-service", "db-service" },
      }
      assert.is_true(sw.is_env(env))
      assert.equals("troubleshooting", env.name)
      assert.equals("memory_leak", env.scenario)
      assert.same({ "user-service", "db-service" }, env.services)
    end)

    it("creates with minimal spec (name only)", function()
      local env = sw.env "empty" {}
      assert.is_true(sw.is_env(env))
      assert.equals("empty", env.name)
    end)

    it("preserves arbitrary params", function()
      local env = sw.env "custom" {
        difficulty = "hard",
        seed = 42,
        nested = { a = 1, b = 2 },
      }
      assert.equals("hard", env.difficulty)
      assert.equals(42, env.seed)
      assert.same({ a = 1, b = 2 }, env.nested)
    end)
  end)

  -- ============================================================
  -- Validation
  -- ============================================================

  describe("validation", function()
    it("rejects non-string name", function()
      h.assert_error_contains(function()
        sw.env(42)
      end, "name must be string")
    end)

    it("rejects non-table spec", function()
      h.assert_error_contains(function()
        sw.env "test" "bad"
      end, "spec must be a table")
    end)
  end)
end)
