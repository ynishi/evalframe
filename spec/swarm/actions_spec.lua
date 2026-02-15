local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

describe("sw.action / sw.actions", function()

  -- ============================================================
  -- sw.action: single action declaration
  -- ============================================================

  describe("sw.action", function()
    it("creates action with name and description", function()
      local a = sw.action "CheckStatus" {
        description = "Check service health",
      }
      assert.is_true(sw.is_action(a))
      assert.equals("CheckStatus", a.name)
      assert.equals("Check service health", a.description)
    end)

    it("accepts optional target field", function()
      local a = sw.action "ReadLogs" {
        description = "Read service logs",
        target = "service",
      }
      assert.equals("service", a.target)
    end)

    it("accepts arbitrary params", function()
      local a = sw.action "Custom" {
        description = "test",
        cost = 5,
        tags = { "debug" },
      }
      assert.equals(5, a.cost)
      assert.same({ "debug" }, a.tags)
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
      assert.is_true(sw.is_action_space(space))
      assert.equals(2, #space.actions)
      assert.equals("A", space.actions[1].name)
      assert.equals("B", space.actions[2].name)
    end)

    it("provides lookup by name", function()
      local space = sw.actions {
        sw.action "CheckStatus" { description = "check" },
        sw.action "ReadLogs"    { description = "read" },
      }
      assert.equals("check", space.by_name["CheckStatus"].description)
      assert.equals("read",  space.by_name["ReadLogs"].description)
      assert.is_nil(space.by_name["NonExistent"])
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
