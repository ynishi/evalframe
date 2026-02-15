--[[
  swarm/env.lua — Environment declaration

  Usage:
    local sw = require("evalframe.swarm")

    local env = sw.env "troubleshooting" {
      scenario = "memory_leak",
      services = { "user-service", "db-service" },
    }
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

    local env = { _tag = ENV_TAG, name = name }
    for k, v in pairs(spec) do
      env[k] = v
    end
    return env
  end
end

function M.is_env(v)
  return type(v) == "table" and v._tag == ENV_TAG
end

return M
