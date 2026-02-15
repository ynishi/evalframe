local sw = require("evalframe.swarm")
local h  = require("spec.spec_helper")

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

      assert.equals("function", type(provider))
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

      assert.equals("solve the problem", captured_config.input)
      assert.is_true(sw.is_env(captured_config.env))
      assert.is_true(sw.is_action_space(captured_config.actions))
      assert.is_true(sw.is_swarm_config(captured_config.swarm))
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
      assert.equals("string", type(resp.text))
      assert.equals("number", type(resp.latency_ms))

      -- SwarmTrace fields
      assert.is_true(sw.is_trace(resp))
      assert.equals(true, resp.success)
      assert.equals(5, resp.ticks)
      assert.equals("success", resp.termination)
      assert.equals(1, #resp.actions)
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
      assert.equals("number", type(resp.latency_ms))
      assert.is_true(resp.latency_ms >= 0)
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
      assert.equals(42.5, resp.latency_ms)
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
      assert.equals("", resp.text)
      assert.truthy(resp.error)
      assert.truthy(resp.error:find("connection refused"))
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
