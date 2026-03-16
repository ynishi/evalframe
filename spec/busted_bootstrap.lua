--[[
  spec/busted_bootstrap.lua — Inject Lua-native `std` global for busted

  In production, the Rust host injects mlua-batteries as the `std` global.
  busted runs on a plain Lua VM without the Rust host, so this bootstrap
  constructs a minimal `std` compatible table from Lua-native libraries.

  Loaded via `.busted` helper before any spec file.
]]

if rawget(_G, "std") then
  return  -- already injected (running under Rust host)
end

local std = {}

-- ============================================================
-- json — lua-cjson
-- ============================================================

local ok, cjson = pcall(require, "cjson")
if ok then
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

  std.json = {
    decode = function(str)
      return sanitize_null(cjson.decode(str))
    end,
    encode = function(tbl)
      return cjson.encode(tbl)
    end,
  }
else
  error("busted_bootstrap: lua-cjson not found. Install via: luarocks install lua-cjson")
end

-- ============================================================
-- fs — io.open based
-- ============================================================

std.fs = {
  read = function(path)
    local f, err = io.open(path, "r")
    if not f then error(string.format("fs.read: %s", err), 2) end
    local content, read_err = f:read("*a")
    f:close()
    if content == nil then
      error(string.format("fs.read: read failed: %s", read_err or "unknown"), 2)
    end
    return content
  end,
  is_file = function(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
  end,
}

-- ============================================================
-- time — socket.gettime or os.time fallback
-- ============================================================

std.time = {}
do
  local sok, socket = pcall(require, "socket")
  if sok and socket.gettime then
    std.time.now = socket.gettime
  else
    std.time.now = os.time
  end
end

rawset(_G, "std", std)
