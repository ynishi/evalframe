--[[
  spec/spec_helper.lua — Shared test utilities for evalframe
]]

local M = {}

-- ============================================================
-- Assertion helpers
-- ============================================================

function M.assert_error_contains(fn, expected)
  local ok, err = pcall(fn)
  assert(not ok, "expected an error but none was raised")
  local msg = tostring(err)
  assert(
    msg:find(expected, 1, true),
    string.format("error message:\n  %s\ndoes not contain:\n  %s", msg, expected)
  )
end

function M.assert_no_error(fn)
  local ok, result = pcall(fn)
  assert(ok, string.format("unexpected error: %s", tostring(result)))
  return result
end

-- ============================================================
-- Table helpers
-- ============================================================

function M.table_count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function M.sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- ============================================================
-- Mock provider (delegates to providers/mock)
-- ============================================================

local mock = require("evalframe.providers.mock")

M.mock_provider   = mock.map
M.static_provider = mock.static

return M
