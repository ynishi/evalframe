local std = require("evalframe.std")
local h   = require("spec.spec_helper")

-- ============================================================
-- Helper: reload evalframe.std with a mocked batteries global.
--
-- Temporarily clears package.loaded["evalframe.std"], injects
-- a mock `std` global, re-requires, then restores.
-- ============================================================

--- Reload std.lua under a mocked batteries environment.
--- @param mock_batteries  table  Mock `std` global (keys: json, fs, time, http)
--- @return table  freshly-loaded evalframe.std
local function reload_std_with_batteries(mock_batteries)
  local saved = {
    std_module  = package.loaded["evalframe.std"],
    std_global  = rawget(_G, "std"),
  }

  package.loaded["evalframe.std"] = nil
  rawset(_G, "std", mock_batteries)

  local ok, result = pcall(require, "evalframe.std")

  rawset(_G, "std", saved.std_global)
  package.loaded["evalframe.std"] = saved.std_module

  if not ok then error(result, 2) end
  return result
end

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("std", function()

  -- ============================================================
  -- fs operations (via batteries adapter)
  -- ============================================================

  describe("fs.read_file", function()
    it("reads existing file", function()
      local content = std.fs.read_file("evalframe/init.lua")
      expect(content:find("evalframe", 1, true)).to.be.truthy()
    end)

    it("errors on non-existent file", function()
      h.assert_error_contains(function()
        std.fs.read_file("does_not_exist_xyz.lua")
      end, "No such file")
    end)
  end)

  describe("fs.file_exists", function()
    it("returns true for existing file", function()
      expect(std.fs.file_exists("evalframe/init.lua")).to.equal(true)
    end)

    it("returns false for non-existent file", function()
      expect(std.fs.file_exists("does_not_exist_xyz.lua")).to.equal(false)
    end)
  end)

  -- ============================================================
  -- json
  -- ============================================================

  describe("json", function()
    it("decodes JSON string", function()
      local t = std.json.decode('{"a":1}')
      expect(t.a).to.equal(1)
    end)

    it("encodes table to JSON", function()
      local s = std.json.encode({ a = 1 })
      expect(s:find('"a"', 1, true)).to.be.truthy()
    end)
  end)

  -- ============================================================
  -- time
  -- ============================================================

  describe("time", function()
    it("returns epoch seconds as number", function()
      local t = std.time()
      expect(type(t)).to.equal("number")
      expect(t > 1000000000).to.be.truthy()
    end)
  end)

  -- ============================================================
  -- batteries adapter: API mapping
  -- ============================================================

  describe("batteries adapter", function()
    it("maps batteries.fs.read to read_file", function()
      local called_with
      local mock = {
        json = { decode = tostring, encode = tostring },
        fs = {
          read    = function(p) called_with = p; return "content" end,
          is_file = function(p) return true end,
        },
        time = { now = function() return 12345.0 end },
      }
      local s = reload_std_with_batteries(mock)
      expect(s.fs.read_file("valid/path.lua")).to.equal("content")
      expect(called_with).to.equal("valid/path.lua")
    end)

    it("maps batteries.fs.is_file to file_exists", function()
      local called_with
      local mock = {
        json = { decode = tostring, encode = tostring },
        fs = {
          read    = function(p) return "" end,
          is_file = function(p) called_with = p; return true end,
        },
        time = { now = function() return 12345.0 end },
      }
      local s = reload_std_with_batteries(mock)
      expect(s.fs.file_exists("valid/path.lua")).to.equal(true)
      expect(called_with).to.equal("valid/path.lua")
    end)

    it("maps batteries.time.now to callable time", function()
      local now_fn = function() return 99999.0 end
      local mock = {
        json = { decode = tostring, encode = tostring },
        fs = { read = tostring, is_file = tostring },
        time = { now = now_fn },
      }
      local s = reload_std_with_batteries(mock)
      expect(s.time).to.equal(now_fn)
    end)

    it("passes through json directly", function()
      local mock_json = { decode = function() return "X" end, encode = tostring }
      local mock = {
        json = mock_json,
        fs = { read = tostring, is_file = tostring },
        time = { now = function() return 0 end },
      }
      local s = reload_std_with_batteries(mock)
      expect(s.json).to.equal(mock_json)
    end)

    it("passes through http directly", function()
      local mock_http = { get = function() return "resp" end }
      local mock = {
        json = { decode = tostring, encode = tostring },
        fs = { read = tostring, is_file = tostring },
        time = { now = function() return 0 end },
        http = mock_http,
      }
      local s = reload_std_with_batteries(mock)
      expect(s.http).to.equal(mock_http)
    end)

    it("leaves http nil when batteries has no http", function()
      local mock = {
        json = { decode = tostring, encode = tostring },
        fs = { read = tostring, is_file = tostring },
        time = { now = function() return 0 end },
      }
      local s = reload_std_with_batteries(mock)
      expect(s.http).to.equal(nil)
    end)

    it("errors when batteries.json is missing", function()
      local mock = {
        fs = { read = tostring, is_file = tostring },
        time = { now = function() return 0 end },
      }
      h.assert_error_contains(function()
        reload_std_with_batteries(mock)
      end, "batteries.json is required")
    end)

    it("errors when batteries.fs is missing", function()
      local mock = {
        json = { decode = tostring, encode = tostring },
        time = { now = function() return 0 end },
      }
      h.assert_error_contains(function()
        reload_std_with_batteries(mock)
      end, "batteries.fs is required")
    end)

    it("errors when batteries.time.now is missing", function()
      local mock = {
        json = { decode = tostring, encode = tostring },
        fs = { read = tostring, is_file = tostring },
      }
      h.assert_error_contains(function()
        reload_std_with_batteries(mock)
      end, "batteries.time.now is required")
    end)

    it("errors when std global is missing", function()
      local saved = {
        std_module = package.loaded["evalframe.std"],
        std_global = rawget(_G, "std"),
      }
      package.loaded["evalframe.std"] = nil
      rawset(_G, "std", nil)

      local ok, err = pcall(require, "evalframe.std")

      rawset(_G, "std", saved.std_global)
      package.loaded["evalframe.std"] = saved.std_module

      expect(ok).to.equal(false)
      expect(tostring(err):find("std.*global not found", 1, false)).to.be.truthy()
    end)
  end)
end)
