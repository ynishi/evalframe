--[[
  swarm/trace.lua — SwarmTrace construction and query helpers

  SwarmTrace extends the evalframe response contract with Swarm-specific
  fields (actions, metrics, termination, etc.). The trace is the primary
  data object that graders inspect post-execution.

  All grader access to trace fields should go through the accessor
  functions in this module, not via direct field access.

  Usage:
    local sw = require("evalframe.swarm")

    local t = sw.trace {
      text = "done", success = true, ticks = 10,
      termination = "success",
      actions = { { tick = 1, worker = "w-0", action = "Act", result = "ok" } },
      metrics = { task_completion = 1.0 },
    }

    sw.trace_at_tick(t, 5)
    sw.trace_actions_by_worker(t, "w-0")
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

--- Shallow-copy an array table.
local function copy_list(t)
  local out = {}
  for i, v in ipairs(t) do out[i] = v end
  return out
end

--- Shallow-copy a hash table.
local function copy_table(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- Validate a single action record.
local function validate_action_record(a, idx)
  if type(a) ~= "table" then
    error(string.format("sw.trace: actions[%d] must be a table", idx), 3)
  end
  if type(a.tick) ~= "number" then
    error(string.format("sw.trace: actions[%d].tick must be number, got %s", idx, type(a.tick)), 3)
  end
  if type(a.worker) ~= "string" then
    error(string.format("sw.trace: actions[%d].worker must be string, got %s", idx, type(a.worker)), 3)
  end
  if type(a.action) ~= "string" then
    error(string.format("sw.trace: actions[%d].action must be string, got %s", idx, type(a.action)), 3)
  end
end

function M.build(raw)
  if type(raw) ~= "table" then
    error("sw.trace: must be a table", 2)
  end

  -- actions (required)
  if raw.actions == nil then
    error("sw.trace: actions is required", 2)
  end
  if type(raw.actions) ~= "table" then
    error("sw.trace: actions must be a table", 2)
  end
  for i, a in ipairs(raw.actions) do
    validate_action_record(a, i)
  end

  -- termination (required, enum)
  if raw.termination == nil then
    error("sw.trace: termination is required", 2)
  end
  if not VALID_TERMINATIONS[raw.termination] then
    error(string.format(
      "sw.trace: termination must be 'success', 'failure', or 'timeout', got '%s'",
      tostring(raw.termination)
    ), 2)
  end

  -- Defensive copy to prevent caller mutation.
  local copied_actions = copy_list(raw.actions)
  local copied_metrics = type(raw.metrics) == "table" and copy_table(raw.metrics) or {}

  return {
    _tag        = TRACE_TAG,
    text        = type(raw.text) == "string" and raw.text or "",
    success     = raw.success == true,
    ticks       = type(raw.ticks) == "number" and raw.ticks or 0,
    termination = raw.termination,
    actions     = copied_actions,
    metrics     = copied_metrics,
    latency_ms  = type(raw.latency_ms) == "number" and raw.latency_ms or nil,
  }
end

function M.is_trace(v)
  return type(v) == "table" and v._tag == TRACE_TAG
end

-- ============================================================
-- Scalar accessors (preferred over direct field access)
-- ============================================================

---@param trace table  SwarmTrace
---@return boolean
function M.succeeded(trace)
  return trace.success == true
end

---@param trace table  SwarmTrace
---@return number
function M.tick_count(trace)
  return trace.ticks
end

---@param trace table  SwarmTrace
---@param name string  Metric name
---@return any|nil  Metric value, or nil if not present
function M.metric(trace, name)
  return trace.metrics and trace.metrics[name]
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
  for _, a in ipairs(trace.actions) do
    if a.action == action_name then return true end
  end
  return false
end

-- ============================================================
-- actions_list: raw action records (ordered)
-- ============================================================

---@param trace table  SwarmTrace
---@return table[]  Action records in tick order
function M.actions_list(trace)
  return trace.actions
end

-- ============================================================
-- find_first_action: tick of first occurrence, or nil
-- ============================================================

---@param trace table  SwarmTrace
---@param action_name string
---@return number|nil  Tick number, or nil if action never taken
function M.find_first_action(trace, action_name)
  for _, a in ipairs(trace.actions) do
    if a.action == action_name then
      return a.tick
    end
  end
  return nil
end

return M
