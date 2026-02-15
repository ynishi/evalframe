--[[
  swarm/config.lua — Swarm configuration declaration

  Usage:
    local sw = require("evalframe.swarm")

    local cfg = sw.swarm {
      workers   = 3,
      managers  = 1,
      max_ticks = 20,
      strategy  = "ucb1",
    }
]]

local M = {}

local SWARM_CONFIG_TAG = {}

function M.build(spec)
  if type(spec) ~= "table" then
    error("sw.swarm: spec must be a table", 2)
  end

  if spec.workers == nil then
    error("sw.swarm: workers is required", 2)
  end
  if type(spec.workers) ~= "number" or spec.workers < 1 or spec.workers ~= math.floor(spec.workers) then
    error("sw.swarm: workers must be a positive integer", 2)
  end

  if spec.max_ticks == nil then
    error("sw.swarm: max_ticks is required", 2)
  end
  if type(spec.max_ticks) ~= "number" or spec.max_ticks < 1 or spec.max_ticks ~= math.floor(spec.max_ticks) then
    error("sw.swarm: max_ticks must be a positive integer", 2)
  end

  local cfg = { _tag = SWARM_CONFIG_TAG }
  for k, v in pairs(spec) do
    cfg[k] = v
  end

  -- Defaults
  if cfg.managers == nil then cfg.managers = 1 end

  return cfg
end

function M.is_swarm_config(v)
  return type(v) == "table" and v._tag == SWARM_CONFIG_TAG
end

return M
