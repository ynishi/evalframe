--[[
  swarm/trace.lua — SwarmTrace construction and query helpers

  SwarmTrace extends the evalframe response contract with Swarm-specific
  fields (actions, metrics, termination, etc.). The trace is the primary
  data object that graders inspect post-execution.

  Usage:
    local sw = require("evalframe.swarm")

    local t = sw.trace {
      text = "done", success = true, ticks = 10,
      termination = "success",
      actions = { { tick = 1, worker = "w-0", action = "Act", result = "ok" } },
      metrics = { task_completion = 1.0 },
    }

    local snap = sw.trace_at_tick(t, 5)
    local w0   = sw.trace_actions_by_worker(t, "w-0")
]]

local M = {}

local TRACE_TAG = {}

local VALID_TERMINATIONS = {
  success = true,
  failure = true,
  timeout = true,
}

-- ============================================================
-- Construction
-- ============================================================

function M.build(raw)
  if type(raw) ~= "table" then
    error("sw.trace: must be a table", 2)
  end

  if raw.actions == nil then
    error("sw.trace: actions is required", 2)
  end

  if raw.termination == nil then
    error("sw.trace: termination is required", 2)
  end
  if not VALID_TERMINATIONS[raw.termination] then
    error(string.format(
      "sw.trace: termination must be 'success', 'failure', or 'timeout', got '%s'",
      tostring(raw.termination)
    ), 2)
  end

  local trace = { _tag = TRACE_TAG }
  for k, v in pairs(raw) do
    trace[k] = v
  end

  -- Defaults
  if trace.text == nil then trace.text = "" end
  if trace.success == nil then trace.success = false end
  if trace.ticks == nil then trace.ticks = 0 end
  if trace.metrics == nil then trace.metrics = {} end

  return trace
end

function M.is_trace(v)
  return type(v) == "table" and v._tag == TRACE_TAG
end

-- ============================================================
-- at_tick: snapshot of state at a given tick
-- ============================================================

--- Return actions and counts up to (inclusive) the given tick.
---@param trace table  SwarmTrace
---@param tick number  Tick number
---@return table { actions, action_count, action_counts }
function M.at_tick(trace, tick)
  local filtered = {}
  local counts = {}

  for _, a in ipairs(trace.actions) do
    if a.tick <= tick then
      filtered[#filtered + 1] = a
      local name = a.action
      counts[name] = (counts[name] or 0) + 1
    end
  end

  return {
    actions       = filtered,
    action_count  = #filtered,
    action_counts = counts,
  }
end

-- ============================================================
-- actions_by_worker: filter actions for a specific worker
-- ============================================================

---@param trace table  SwarmTrace
---@param worker_id string
---@return table[]
function M.actions_by_worker(trace, worker_id)
  local filtered = {}
  for _, a in ipairs(trace.actions) do
    if a.worker == worker_id then
      filtered[#filtered + 1] = a
    end
  end
  return filtered
end

-- ============================================================
-- action_count: count occurrences of a named action
-- ============================================================

---@param trace table  SwarmTrace
---@param action_name string
---@return number
function M.action_count(trace, action_name)
  local count = 0
  for _, a in ipairs(trace.actions) do
    if a.action == action_name then
      count = count + 1
    end
  end
  return count
end

-- ============================================================
-- has_action: check if action was ever taken
-- ============================================================

---@param trace table  SwarmTrace
---@param action_name string
---@return boolean
function M.has_action(trace, action_name)
  return M.action_count(trace, action_name) > 0
end

return M
