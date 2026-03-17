local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("sw.action / sw.actions", function()

  -- ============================================================
  -- sw.action: single action declaration
  -- ============================================================

  describe("sw.action", function()
    it("creates action with name and description", function()
      local a = sw.action "CheckStatus" {
        description = "Check service health",
      }
      expect(sw.is_action(a)).to.equal(true)
      expect(a.name).to.equal("CheckStatus")
      expect(a.description).to.equal("Check service health")
    end)

    it("stores non-description fields in context", function()
      local a = sw.action "ReadLogs" {
        description = "Read service logs",
        target = "service",
      }
      expect(a.context.target).to.equal("service")
    end)

    it("stores arbitrary params in context", function()
      local a = sw.action "Custom" {
        description = "test",
        cost = 5,
        tags = { "debug" },
      }
      expect(a.context.cost).to.equal(5)
      expect(a.context.tags).to.equal({ "debug" })
    end)

    it("has empty context when only description provided", function()
      local a = sw.action "Simple" { description = "simple" }
      expect(a.context).to.equal({})
    end)
  end)

  -- ============================================================
  -- sw.action: validation
  -- ============================================================

  describe("sw.action validation", function()
    it("rejects non-string name", function()
      h.assert_error_contains(function()
        sw.action(42)
      end, "name must be string")
    end)

    it("rejects missing description", function()
      h.assert_error_contains(function()
        sw.action "Bad" {}
      end, "description is required")
    end)

    it("rejects non-string description", function()
      h.assert_error_contains(function()
        sw.action "Bad" { description = 42 }
      end, "description must be string")
    end)
  end)

  -- ============================================================
  -- sw.actions: action space
  -- ============================================================

  describe("sw.actions", function()
    it("creates action space from action list", function()
      local space = sw.actions {
        sw.action "A" { description = "action a" },
        sw.action "B" { description = "action b" },
      }
      expect(sw.is_action_space(space)).to.equal(true)
      expect(#space.actions).to.equal(2)
      expect(space.actions[1].name).to.equal("A")
      expect(space.actions[2].name).to.equal("B")
    end)

    it("provides lookup by name", function()
      local space = sw.actions {
        sw.action "CheckStatus" { description = "check" },
        sw.action "ReadLogs"    { description = "read" },
      }
      expect(space.by_name["CheckStatus"].description).to.equal("check")
      expect( space.by_name["ReadLogs"].description).to.equal("read")
      expect(space.by_name["NonExistent"]).to.equal(nil)
    end)
  end)

  -- ============================================================
  -- sw.actions: validation
  -- ============================================================

  describe("sw.actions validation", function()
    it("rejects empty list", function()
      h.assert_error_contains(function()
        sw.actions {}
      end, "at least 1 action")
    end)

    it("rejects duplicate action names", function()
      h.assert_error_contains(function()
        sw.actions {
          sw.action "A" { description = "first" },
          sw.action "A" { description = "second" },
        }
      end, "duplicate action name")
    end)

    it("rejects non-action entries", function()
      h.assert_error_contains(function()
        sw.actions {
          { name = "fake", description = "not an action" },
        }
      end, "must be an action")
    end)
  end)
end)
