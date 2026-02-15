--[[
  swarm/actions.lua — Action and ActionSpace declarations

  Usage:
    local sw = require("evalframe.swarm")

    local a = sw.action "CheckStatus" { description = "Check service health" }

    local space = sw.actions {
      sw.action "CheckStatus" { description = "Check service health" },
      sw.action "ReadLogs"    { description = "Read logs", target = "service" },
    }
]]

local M = {}

local ACTION_TAG       = {}
local ACTION_SPACE_TAG = {}

-- ============================================================
-- sw.action: single action declaration
-- ============================================================

function M.build_action(name)
  if type(name) ~= "string" then
    error(string.format("sw.action: name must be string, got %s", type(name)), 3)
  end

  return function(spec)
    if type(spec) ~= "table" then
      error(string.format("sw.action '%s': spec must be a table", name), 3)
    end

    if spec.description == nil then
      error(string.format("sw.action '%s': description is required", name), 3)
    end
    if type(spec.description) ~= "string" then
      error(string.format("sw.action '%s': description must be string, got %s", name, type(spec.description)), 3)
    end

    local action = { _tag = ACTION_TAG, name = name }
    for k, v in pairs(spec) do
      action[k] = v
    end
    return action
  end
end

function M.is_action(v)
  return type(v) == "table" and v._tag == ACTION_TAG
end

-- ============================================================
-- sw.actions: action space (validated list + name index)
-- ============================================================

function M.build_action_space(list)
  if type(list) ~= "table" or #list < 1 then
    error("sw.actions: at least 1 action required", 2)
  end

  local actions = {}
  local by_name = {}

  for i, entry in ipairs(list) do
    if not M.is_action(entry) then
      error(string.format("sw.actions[%d]: must be an action (use sw.action)", i), 2)
    end
    if by_name[entry.name] then
      error(string.format("sw.actions: duplicate action name '%s'", entry.name), 2)
    end
    actions[#actions + 1] = entry
    by_name[entry.name] = entry
  end

  return {
    _tag    = ACTION_SPACE_TAG,
    actions = actions,
    by_name = by_name,
  }
end

function M.is_action_space(v)
  return type(v) == "table" and v._tag == ACTION_SPACE_TAG
end

return M
