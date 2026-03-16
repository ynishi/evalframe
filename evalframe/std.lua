--[[
  std.lua — stdlib adapter

  Host (Rust) injects mlua-batteries as the `std` global table.
  This module adapts batteries' API to evalframe's internal contract.

  Contract:
    std.json.decode(str) → table
    std.json.encode(tbl) → string
    std.fs.read_file(path) → string
    std.fs.file_exists(path) → boolean
    std.time() → number (epoch seconds)
    std.http (optional) — passthrough from batteries

  Boundary:
    Security (path traversal, sandboxing) is enforced by batteries' Rust
    implementation via PathPolicy. No Lua-side guards needed.
]]

local batteries = rawget(_G, "std")

if not batteries then
  error(
    "evalframe.std: 'std' global not found. "
    .. "evalframe requires a Rust host that injects mlua-batteries.",
    2
  )
end

local M = {}

-- ============================================================
-- json — direct passthrough (API matches)
-- ============================================================

M.json = batteries.json

-- ============================================================
-- fs — adapt batteries API names to evalframe contract
--
-- batteries: read(path), is_file(path)
-- evalframe: read_file(path), file_exists(path)
-- ============================================================

if batteries.fs then
  M.fs = {
    read_file = batteries.fs.read,
    file_exists = batteries.fs.is_file,
  }
end

-- ============================================================
-- time — adapt from table to callable
--
-- batteries: std.time.now() → epoch seconds (f64)
-- evalframe: std.time()     → epoch seconds
-- ============================================================

if batteries.time and batteries.time.now then
  M.time = batteries.time.now
end

-- ============================================================
-- http — passthrough (optional)
-- ============================================================

M.http = batteries.http

return M
