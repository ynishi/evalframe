--[[
  evalframe.swarm — Swarm evaluation DSL

  Provides declarative primitives for Swarm-based evaluation.
  The actual tick loop (runner) is user-provided — either in Lua
  or via __rustlib.swarm.

  Usage:
    local sw = require("evalframe.swarm")

    local env = sw.env "troubleshooting" { scenario = "memory_leak" }

    local actions = sw.actions {
      sw.action "CheckStatus" { description = "Check service health" },
      sw.action "ReadLogs"    { description = "Read logs", target = "service" },
    }

    local swarm_cfg = sw.swarm { workers = 3, max_ticks = 20 }

    local provider = sw.provider(my_runner, {
      env = env, actions = actions, swarm = swarm_cfg,
    })
]]

local env_mod     = require("evalframe.swarm.env")
local actions_mod = require("evalframe.swarm.actions")
local config_mod  = require("evalframe.swarm.config")
local trace_mod   = require("evalframe.swarm.trace")
local provider_mod = require("evalframe.swarm.provider")

local M = {}

-- Declarations
M.env    = env_mod.build
M.action = actions_mod.build_action
M.actions = actions_mod.build_action_space
M.swarm  = config_mod.build

-- Trace construction
M.trace                   = trace_mod.build

-- Trace scalar accessors
M.trace_succeeded         = trace_mod.succeeded
M.trace_tick_count        = trace_mod.tick_count
M.trace_metric            = trace_mod.metric

-- Trace query helpers
M.trace_at_tick           = trace_mod.at_tick
M.trace_actions_by_worker = trace_mod.actions_by_worker
M.trace_action_count      = trace_mod.action_count
M.trace_has_action        = trace_mod.has_action
M.trace_actions_list      = trace_mod.actions_list
M.trace_find_first_action = trace_mod.find_first_action

-- Provider adapter
M.provider = provider_mod.build

-- Graders
M.graders = require("evalframe.swarm.graders")

-- Type checks
M.is_env          = env_mod.is_env
M.is_action       = actions_mod.is_action
M.is_action_space = actions_mod.is_action_space
M.is_swarm_config = config_mod.is_swarm_config
M.is_trace        = trace_mod.is_trace

return M
