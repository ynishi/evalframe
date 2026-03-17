local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("sw.provider", function()

  local env = sw.env "test_env" { scenario = "basic" }
  local actions = sw.actions {
    sw.action "Act" { description = "do something" },
  }
  local swarm_cfg = sw.swarm { workers = 1, max_ticks = 5 }

  -- ============================================================
  -- Construction
  -- ============================================================

  describe("construction", function()
    it("wraps a runner into an evalframe provider function", function()
      local runner = function(_config)
        return {
          text        = "done",
          success     = true,
          ticks       = 3,
          termination = "success",
          actions     = {},
          metrics     = {},
        }
      end

      local provider = sw.provider(runner, {
        env     = env,
        actions = actions,
        swarm   = swarm_cfg,
      })

      expect(type(provider)).to.equal("function")
    end)

    it("calls runner with merged config including input", function()
      local captured_config

      local runner = function(config)
        captured_config = config
        return {
          text = "", success = true, ticks = 1,
          termination = "success", actions = {}, metrics = {},
        }
      end

      local provider = sw.provider(runner, {
        env     = env,
        actions = actions,
        swarm   = swarm_cfg,
      })

      provider("solve the problem")

      expect(captured_config.input).to.equal("solve the problem")
      expect(sw.is_env(captured_config.env)).to.equal(true)
      expect(sw.is_action_space(captured_config.actions)).to.equal(true)
      expect(sw.is_swarm_config(captured_config.swarm)).to.equal(true)
    end)
  end)

  -- ============================================================
  -- Response contract
  -- ============================================================

  describe("response contract", function()
    it("returns a valid SwarmTrace as response", function()
      local runner = function(_config)
        return {
          text        = "resolved",
          success     = true,
          ticks       = 5,
          termination = "success",
          actions     = {
            { tick = 1, worker = "w-0", action = "Act", result = "ok" },
          },
          metrics     = { task_completion = 1.0 },
        }
      end

      local provider = sw.provider(runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local resp = provider("input")

      -- evalframe response contract fields
      expect(type(resp.text)).to.equal("string")
      expect(type(resp.latency_ms)).to.equal("number")

      -- SwarmTrace fields
      expect(sw.is_trace(resp)).to.equal(true)
      expect(resp.success).to.equal(true)
      expect(resp.ticks).to.equal(5)
      expect(resp.termination).to.equal("success")
      expect(#resp.actions).to.equal(1)
    end)

    it("measures latency when runner does not provide it", function()
      local runner = function(_config)
        return {
          text = "", success = true, ticks = 1,
          termination = "success", actions = {}, metrics = {},
        }
      end

      local provider = sw.provider(runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local resp = provider("input")
      expect(type(resp.latency_ms)).to.equal("number")
      expect(resp.latency_ms >= 0).to.equal(true)
    end)

    it("preserves runner-provided latency_ms", function()
      local runner = function(_config)
        return {
          text = "", success = true, ticks = 1,
          termination = "success", actions = {}, metrics = {},
          latency_ms = 42.5,
        }
      end

      local provider = sw.provider(runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local resp = provider("input")
      expect(resp.latency_ms).to.equal(42.5)
    end)

    it("does not mutate runner's return table", function()
      local returned_table
      local runner = function(_config)
        returned_table = {
          text = "", success = true, ticks = 1,
          termination = "success", actions = {}, metrics = {},
        }
        return returned_table
      end

      local provider = sw.provider(runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      provider("input")
      -- runner's return table should not have latency_ms injected
      expect(returned_table.latency_ms).to.equal(nil)
    end)
  end)

  -- ============================================================
  -- Error handling
  -- ============================================================

  describe("error handling", function()
    it("returns error response when runner throws", function()
      local runner = function(_config)
        error("connection refused")
      end

      local provider = sw.provider(runner, {
        env = env, actions = actions, swarm = swarm_cfg,
      })

      local resp = provider("input")
      expect(resp.text).to.equal("")
      expect(resp.error).to.be.truthy()
      expect(resp.error:find("connection refused")).to.be.truthy()
    end)
  end)

  -- ============================================================
  -- Validation
  -- ============================================================

  describe("validation", function()
    it("rejects non-function runner", function()
      h.assert_error_contains(function()
        sw.provider("not a function", {
          env = env, actions = actions, swarm = swarm_cfg,
        })
      end, "runner must be a function")
    end)

    it("rejects missing env", function()
      h.assert_error_contains(function()
        sw.provider(function() end, {
          actions = actions, swarm = swarm_cfg,
        })
      end, "env is required")
    end)

    it("rejects missing actions", function()
      h.assert_error_contains(function()
        sw.provider(function() end, {
          env = env, swarm = swarm_cfg,
        })
      end, "actions is required")
    end)

    it("rejects missing swarm config", function()
      h.assert_error_contains(function()
        sw.provider(function() end, {
          env = env, actions = actions,
        })
      end, "swarm is required")
    end)
  end)
end)
