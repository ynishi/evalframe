--[[
  providers/algocline.lua — algocline strategy provider

  Runs an algocline strategy package as an evalframe provider.
  Only works inside algocline's mlua VM (requires `alc` global).

  Usage:
    local ef = require("evalframe")

    -- Run "reflect" strategy on each case input
    local provider = ef.providers.algocline { strategy = "reflect" }

    -- With strategy-specific options
    local provider = ef.providers.algocline {
      strategy = "ucb",
      opts = { rounds = 5 },
    }

    -- Use in suite
    local s = ef.suite "eval_reflect" {
      provider = provider,
      ef.bind { ef.graders.contains },
      cases = { ef.case { input = "Review this code...", expected = "..." } },
    }
]]

local std = require("evalframe.std")

local M = {}

--- Extract text from a strategy result.
---@param result any  Strategy return value (typically ctx table with .result)
---@return string
local function extract_text(result)
  if type(result) == "string" then
    return result
  end
  if type(result) ~= "table" then
    return tostring(result)
  end
  -- ctx.result is the conventional output field
  local r = result.result
  if r == nil then
    -- Fallback: try encoding the whole result
    if alc and alc.json_encode then
      return alc.json_encode(result)
    end
    return tostring(result)
  end
  if type(r) == "string" then
    return r
  end
  if type(r) == "table" then
    -- Nested result: try .answer, .summary, .output, .text
    for _, key in ipairs({ "answer", "summary", "output", "text" }) do
      if type(r[key]) == "string" then
        return r[key]
      end
    end
    if alc and alc.json_encode then
      return alc.json_encode(r)
    end
  end
  return tostring(r)
end

--- Create an algocline strategy provider.
---@param opts table  { strategy: string, opts?: table }
---@return function provider(input) → response
setmetatable(M, {
  __call = function(_, opts)
    opts = opts or {}

    local strategy_name = opts.strategy
    if not strategy_name or type(strategy_name) ~= "string" then
      error("algocline provider: 'strategy' must be a string", 2)
    end

    -- Verify alc global is available (running inside algocline VM)
    if type(alc) ~= "table" or type(alc.llm) ~= "function" then
      error("algocline provider: requires algocline VM (alc global not found)", 2)
    end

    local strategy_opts = opts.opts or {}

    return function(input)
      local strategy = require(strategy_name)
      if type(strategy.run) ~= "function" then
        error(string.format(
          "algocline provider: package '%s' has no run() function", strategy_name
        ), 2)
      end

      -- Build ctx: task = input, merge strategy opts
      local run_ctx = { task = input }
      for k, v in pairs(strategy_opts) do
        run_ctx[k] = v
      end

      local start = std.time()
      local ok, result = pcall(strategy.run, run_ctx)
      local elapsed = (std.time() - start) * 1000

      if not ok then
        return {
          text       = "",
          model      = "algocline:" .. strategy_name,
          error      = tostring(result),
          latency_ms = elapsed,
        }
      end

      local text = extract_text(result)
      return {
        text       = text,
        model      = "algocline:" .. strategy_name,
        latency_ms = elapsed,
        raw        = result,
      }
    end
  end,
})

return M
