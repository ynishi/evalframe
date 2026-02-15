--[[
  swarm/env.lua — Environment declaration

  Declares the evaluation scenario context.
  evalframe uses `name` for identification; `context` holds
  domain-specific data consumed by the runner.

  Usage:
    local sw = require("evalframe.swarm")

    local env = sw.env "troubleshooting" {
      scenario = "memory_leak",
      services = { "user-service", "db-service" },
    }
    -- env.name    == "troubleshooting"
    -- env.context == { scenario = "memory_leak", services = { ... } }
]]

local M = {}

local ENV_TAG = {}

function M.build(name)
  if type(name) ~= "string" then
    error(string.format("sw.env: name must be string, got %s", type(name)), 3)
  end

  return function(spec)
    if type(spec) ~= "table" then
      error(string.format("sw.env '%s': spec must be a table", name), 3)
    end

    return {
      _tag    = ENV_TAG,
      name    = name,
      context = spec,
    }
  end
end

function M.is_env(v)
  return type(v) == "table" and v._tag == ENV_TAG
end

return M
