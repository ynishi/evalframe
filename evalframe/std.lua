--[[
  std.lua — Rust-Lua stdlib shim

  Contract: json, fs, time
  Prototype mode: lua-cjson + io.open
  Production mode: Rust injects via mlua before this module loads.

  Usage:
    local std = require("evalframe.std")
    local data = std.json.decode(str)
    local content = std.fs.read_file("path.json")

  mlua injection (Rust side):
    lua.globals().set("__rustlib", injected_table)?;

  Security contract (I/O boundary):
    Prototype (Lua) provides minimal guards only. Full security is
    enforced by the Production (Rust) __rustlib implementation.

    - fs: Path traversal prevention, sandboxing.
           Rust performs canonicalize + base_dir checks.
           Prototype provides basic traversal detection only.
    - loader: load_file executes Lua code.
           Rust builds a sandboxed environment with _ENV restrictions.
           Prototype relies on std.fs path checks only.
]]

local M = {}

-- ============================================================
-- Check for Rust-injected stdlib (mlua production mode)
-- ============================================================
local injected = rawget(_G, "__rustlib")

-- ============================================================
-- json
-- ============================================================
if injected and injected.json then
  M.json = injected.json
else
  local ok, cjson = pcall(require, "cjson")
  if not ok then
    error("std.json: lua-cjson not found. Install via: luarocks install lua-cjson")
  end

  local cjson_null = cjson.null

  local function sanitize_null(v)
    if v == cjson_null then return nil end
    if type(v) == "table" then
      local clean = {}
      for k, val in pairs(v) do
        clean[k] = sanitize_null(val)
      end
      return clean
    end
    return v
  end

  M.json = {
    decode = function(str)
      return sanitize_null(cjson.decode(str))
    end,
    encode = function(tbl)
      return cjson.encode(tbl)
    end,
  }
end

-- ============================================================
-- fs
--
-- Security: Path traversal prevention is this layer's responsibility.
-- Prototype: basic ".." detection only.
-- Production (Rust): strict validation via canonicalize + base_dir constraint.
-- ============================================================

--- Prototype guard: reject obvious path traversal.
--- Production (Rust) replaces this with canonicalize + base_dir check.
local function check_path(path)
  if type(path) ~= "string" or #path == 0 then
    error("std.fs: path must be a non-empty string", 3)
  end
  -- Reject null bytes (Lua string can embed \0, C APIs truncate there)
  if path:find("\0") then
    error("std.fs: path contains null byte", 3)
  end
  -- Reject ".." as a path component (traversal)
  if path == ".."
    or path:find("^%.%./")
    or path:find("/%.%./")
    or path:find("/%.%.$")
  then
    error("std.fs: path traversal detected (contains '..')", 3)
  end
end

if injected and injected.fs then
  M.fs = injected.fs
else
  M.fs = {
    read_file = function(path)
      check_path(path)
      local f, open_err = io.open(path, "r")
      if not f then error(string.format("std.fs.read_file: %s", open_err), 2) end
      local content, read_err = f:read("*a")
      f:close()
      if content == nil then
        error(string.format("std.fs.read_file: read failed: %s", read_err or "unknown"), 2)
      end
      return content
    end,
    file_exists = function(path)
      check_path(path)
      local f = io.open(path, "r")
      if f then f:close(); return true end
      return false
    end,
  }
end

-- ============================================================
-- time — Wall-clock timer
--
-- Prefer socket.gettime (ms precision) over os.time (sec precision).
-- ============================================================

do
  local ok, socket = pcall(require, "socket")
  if ok and socket.gettime then
    M.time = socket.gettime
  else
    M.time = os.time
  end
end

return M
