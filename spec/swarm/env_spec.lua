local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("sw.env", function()

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("creates environment declaration with name and context", function()
      local env = sw.env "troubleshooting" {
        scenario = "memory_leak",
        services = { "user-service", "db-service" },
      }
      expect(sw.is_env(env)).to.equal(true)
      expect(env.name).to.equal("troubleshooting")
      expect(env.context.scenario).to.equal("memory_leak")
      expect(env.context.services).to.equal({ "user-service", "db-service" })
    end)

    it("creates with minimal spec (name only)", function()
      local env = sw.env "empty" {}
      expect(sw.is_env(env)).to.equal(true)
      expect(env.name).to.equal("empty")
      expect(env.context).to.equal({})
    end)

    it("defensive-copies context (caller mutation does not affect env)", function()
      local spec = { scenario = "leak", count = 3 }
      local env = sw.env "test" (spec)
      spec.scenario = "CHANGED"
      spec.injected = true
      expect(env.context.scenario).to.equal("leak")
      expect(env.context.injected).to.equal(nil)
    end)

    it("stores all spec fields in context", function()
      local env = sw.env "custom" {
        difficulty = "hard",
        seed = 42,
        nested = { a = 1, b = 2 },
      }
      expect(env.context.difficulty).to.equal("hard")
      expect(env.context.seed).to.equal(42)
      expect(env.context.nested).to.equal({ a = 1, b = 2 })
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
