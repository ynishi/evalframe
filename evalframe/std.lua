--[[
  std.lua — Rust-Lua stdlib shim

  Contract: json, fs, time, http (optional), exec (optional)

  Resolution order:
    1. __rustlib  — mlua production mode (Rust injects globals)
    2. senl.*     — evalframe CLI host (senl provides Rust helpers)
    3. Lua        — prototype mode (lua-cjson + io.open)

  Usage:
    local std = require("evalframe.std")
    local data = std.json.decode(str)
    local content = std.fs.read_file("path.json")

    -- Available when running under evalframe CLI host (senl)
    if std.http then
      local resp = std.http.get("http://localhost:8000/health")
    end
    if std.exec then
      local result = std.exec.run("ls", { "-la" })
    end

  mlua injection (Rust side):
    lua.globals().set("__rustlib", injected_table)?;

  Security contract (I/O boundary):
    Prototype (Lua) provides minimal guards only. Full security is
    enforced by the Production (Rust) __rustlib or senl implementation.

    - fs: Path traversal prevention, sandboxing.
           Rust performs canonicalize + base_dir checks.
           Prototype provides basic traversal detection only.
    - loader: load_file executes Lua code.
           Rust builds a sandboxed environment with _ENV restrictions.
           Prototype relies on std.fs path checks only.
]]

local M = {}

-- ============================================================
-- Detect runtime environment
-- ============================================================

local injected = rawget(_G, "__rustlib")

-- senl detection: if senl.json is loadable, we're under evalframe CLI host
local senl = {}
if not injected then
  local ok, mod = pcall(require, "senl.json")
  if ok then
    senl.json = mod
    -- Load remaining senl modules (all optional)
    ok, mod = pcall(require, "senl.fs");   if ok then senl.fs = mod end
    ok, mod = pcall(require, "senl.http"); if ok then senl.http = mod end
    ok, mod = pcall(require, "senl.exec"); if ok then senl.exec = mod end
    ok, mod = pcall(require, "senl.time"); if ok then senl.time = mod end
  end
end

-- ============================================================
-- json
--
-- evalframe contract: decode(str), encode(tbl)
-- senl provides:      parse(str),  encode(value)
-- ============================================================

if injected and injected.json then
  M.json = injected.json
elseif senl.json then
  M.json = {
    decode = senl.json.parse,
    encode = senl.json.encode,
  }
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
-- evalframe contract: read_file(path), file_exists(path)
-- senl provides:      read(path),      exists(path)
--
-- Security: Path traversal prevention is this layer's responsibility.
-- Prototype: basic ".." detection only.
-- senl: Lua-side check_path + Rust fs (defense-in-depth).
-- __rustlib: Rust canonicalize + base_dir (trusted, no Lua guard).
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
elseif senl.fs then
  -- Defense-in-depth: apply Lua-side path validation even though senl.fs
  -- is Rust-backed. __rustlib.fs is trusted directly (Rust canonicalize +
  -- base_dir), but senl.fs may not enforce sandboxing constraints.
  M.fs = {
    read_file = function(path)
      check_path(path)
      return senl.fs.read(path)
    end,
    file_exists = function(path)
      check_path(path)
      return senl.fs.exists(path)
    end,
  }
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
-- http (optional)
--
-- Only available under __rustlib or senl host.
-- senl provides: get(url), post(url, body, content_type?)
-- ============================================================

if injected and injected.http then
  M.http = injected.http
elseif senl.http then
  M.http = senl.http
end

-- ============================================================
-- exec (optional)
--
-- Only available under __rustlib or senl host.
-- senl provides: run(cmd, args), capture(cmd, args)
-- ============================================================

if injected and injected.exec then
  M.exec = injected.exec
elseif senl.exec then
  M.exec = senl.exec
end

-- ============================================================
-- time — Wall-clock timer
--
-- Resolution order:
--   1. __rustlib.time — mlua production mode
--   2. senl.time.now  — Rust Instant precision (sub-ms)
--   3. socket.gettime — luasocket (ms precision)
--   4. os.time        — Lua stdlib (second precision)
-- ============================================================

if injected and injected.time then
  M.time = injected.time
elseif senl.time and senl.time.now then
  M.time = senl.time.now
else
  local ok, socket = pcall(require, "socket")
  if ok and socket.gettime then
    M.time = socket.gettime
  else
    M.time = os.time
  end
end

return M
