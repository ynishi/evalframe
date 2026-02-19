local std = require("evalframe.std")
local h   = require("spec.spec_helper")

-- ============================================================
-- Helper: reload evalframe.std with a mocked runtime environment.
--
-- Temporarily clears package.loaded["evalframe.std"], injects
-- mock modules (senl.* or __rustlib), re-requires, then restores.
-- ============================================================

--- Reload std.lua under a mocked senl environment.
--- @param mocks  table  Keys: json, fs, http, exec, time (all optional).
---                       Each value is the mock module to inject.
--- @return table  freshly-loaded evalframe.std
local function reload_std_with_senl(mocks)
  -- Save state
  local saved = {
    std         = package.loaded["evalframe.std"],
    senl_json   = package.loaded["senl.json"],
    senl_fs     = package.loaded["senl.fs"],
    senl_http   = package.loaded["senl.http"],
    senl_exec   = package.loaded["senl.exec"],
    senl_time   = package.loaded["senl.time"],
    rustlib     = rawget(_G, "__rustlib"),
  }

  -- Clear module cache and ensure no __rustlib
  package.loaded["evalframe.std"] = nil
  rawset(_G, "__rustlib", nil)

  -- Inject senl mocks (senl.json is required to trigger senl detection)
  package.loaded["senl.json"] = mocks.json or { parse = tostring, encode = tostring }
  if mocks.fs   then package.loaded["senl.fs"]   = mocks.fs   end
  if mocks.http then package.loaded["senl.http"] = mocks.http end
  if mocks.exec then package.loaded["senl.exec"] = mocks.exec end
  if mocks.time then package.loaded["senl.time"] = mocks.time end

  -- Re-require to exercise the senl resolution path
  local ok, result = pcall(require, "evalframe.std")

  -- Restore state (regardless of success)
  rawset(_G, "__rustlib", saved.rustlib)
  package.loaded["evalframe.std"] = saved.std
  package.loaded["senl.json"]     = saved.senl_json
  package.loaded["senl.fs"]       = saved.senl_fs
  package.loaded["senl.http"]     = saved.senl_http
  package.loaded["senl.exec"]     = saved.senl_exec
  package.loaded["senl.time"]     = saved.senl_time

  if not ok then error(result, 2) end
  return result
end

--- Reload std.lua under a mocked __rustlib environment.
--- @param rustlib  table  Mock __rustlib global (keys: json, fs, time, etc.)
--- @return table  freshly-loaded evalframe.std
local function reload_std_with_rustlib(rustlib)
  local saved = {
    std     = package.loaded["evalframe.std"],
    rustlib = rawget(_G, "__rustlib"),
  }

  package.loaded["evalframe.std"] = nil
  rawset(_G, "__rustlib", rustlib)

  local ok, result = pcall(require, "evalframe.std")

  rawset(_G, "__rustlib", saved.rustlib)
  package.loaded["evalframe.std"] = saved.std

  if not ok then error(result, 2) end
  return result
end

describe("std", function()

  -- ============================================================
  -- fs path validation
  -- ============================================================

  describe("fs.check_path", function()
    it("rejects empty string", function()
      h.assert_error_contains(function()
        std.fs.read_file("")
      end, "non-empty string")
    end)

    it("rejects nil", function()
      h.assert_error_contains(function()
        std.fs.read_file(nil)
      end, "non-empty string")
    end)

    it("rejects null byte in path", function()
      h.assert_error_contains(function()
        std.fs.read_file("foo\0bar.lua")
      end, "null byte")
    end)

    it("rejects null byte in file_exists", function()
      h.assert_error_contains(function()
        std.fs.file_exists("foo\0bar")
      end, "null byte")
    end)

    it("rejects '..' as path", function()
      h.assert_error_contains(function()
        std.fs.read_file("..")
      end, "path traversal")
    end)

    it("rejects '../' prefix traversal", function()
      h.assert_error_contains(function()
        std.fs.read_file("../etc/passwd")
      end, "path traversal")
    end)

    it("rejects mid-path traversal", function()
      h.assert_error_contains(function()
        std.fs.read_file("foo/../../../etc/passwd")
      end, "path traversal")
    end)

    it("rejects trailing '..' traversal", function()
      h.assert_error_contains(function()
        std.fs.read_file("foo/..")
      end, "path traversal")
    end)

    it("rejects traversal in file_exists", function()
      h.assert_error_contains(function()
        std.fs.file_exists("../etc/passwd")
      end, "path traversal")
    end)

    it("allows '...' in path (not traversal)", function()
      -- "..." is not ".." — should not be rejected
      h.assert_error_contains(function()
        std.fs.read_file("foo/.../bar.lua")
      end, "std.fs.read_file")  -- fails on file-not-found, not traversal
    end)
  end)

  -- ============================================================
  -- fs normal operations
  -- ============================================================

  describe("fs.read_file", function()
    it("reads existing file", function()
      local content = std.fs.read_file("evalframe/init.lua")
      assert.truthy(content:find("evalframe", 1, true))
    end)

    it("errors on non-existent file", function()
      h.assert_error_contains(function()
        std.fs.read_file("does_not_exist_xyz.lua")
      end, "std.fs.read_file")
    end)
  end)

  describe("fs.file_exists", function()
    it("returns true for existing file", function()
      assert.is_true(std.fs.file_exists("evalframe/init.lua"))
    end)

    it("returns false for non-existent file", function()
      assert.is_false(std.fs.file_exists("does_not_exist_xyz.lua"))
    end)
  end)

  -- ============================================================
  -- senl backend resolution
  -- ============================================================

  describe("senl backend", function()
    it("maps senl.json.parse to decode", function()
      local called_with
      local mock_json = {
        parse  = function(s) called_with = s; return { ok = true } end,
        encode = function(t) return "encoded" end,
      }
      local s = reload_std_with_senl({ json = mock_json })
      local result = s.json.decode('{"x":1}')
      assert.equal('{"x":1}', called_with)
      assert.same({ ok = true }, result)
    end)

    it("maps senl.json.encode", function()
      local mock_json = {
        parse  = function(s) return {} end,
        encode = function(t) return "ENCODED" end,
      }
      local s = reload_std_with_senl({ json = mock_json })
      assert.equal("ENCODED", s.json.encode({ a = 1 }))
    end)

    it("maps senl.fs.read to read_file with check_path", function()
      local called_with
      local mock_fs = {
        read   = function(p) called_with = p; return "content" end,
        exists = function(p) return true end,
      }
      local s = reload_std_with_senl({ fs = mock_fs })
      assert.equal("content", s.fs.read_file("valid/path.lua"))
      assert.equal("valid/path.lua", called_with)
    end)

    it("maps senl.fs.exists to file_exists with check_path", function()
      local called_with
      local mock_fs = {
        read   = function(p) return "" end,
        exists = function(p) called_with = p; return true end,
      }
      local s = reload_std_with_senl({ fs = mock_fs })
      assert.is_true(s.fs.file_exists("valid/path.lua"))
      assert.equal("valid/path.lua", called_with)
    end)

    it("applies check_path to senl.fs.read_file (traversal rejected)", function()
      local mock_fs = {
        read   = function(p) return "SHOULD NOT REACH" end,
        exists = function(p) return true end,
      }
      local s = reload_std_with_senl({ fs = mock_fs })
      h.assert_error_contains(function()
        s.fs.read_file("../etc/passwd")
      end, "path traversal")
    end)

    it("applies check_path to senl.fs.file_exists (null byte rejected)", function()
      local mock_fs = {
        read   = function(p) return "" end,
        exists = function(p) return true end,
      }
      local s = reload_std_with_senl({ fs = mock_fs })
      h.assert_error_contains(function()
        s.fs.file_exists("foo\0bar")
      end, "null byte")
    end)

    it("passes through senl.http directly", function()
      local mock_http = { get = function() return "resp" end }
      local s = reload_std_with_senl({ http = mock_http })
      assert.equal(mock_http, s.http)
    end)

    it("passes through senl.exec directly", function()
      local mock_exec = { run = function() return "ok" end }
      local s = reload_std_with_senl({ exec = mock_exec })
      assert.equal(mock_exec, s.exec)
    end)

    it("uses senl.time.now for time", function()
      local now_fn = function() return 12345.678 end
      local mock_time = { now = now_fn }
      local s = reload_std_with_senl({ time = mock_time })
      assert.equal(now_fn, s.time)
    end)

    it("leaves http nil when senl.http not available", function()
      local s = reload_std_with_senl({})
      assert.is_nil(s.http)
    end)

    it("leaves exec nil when senl.exec not available", function()
      local s = reload_std_with_senl({})
      assert.is_nil(s.exec)
    end)
  end)

  -- ============================================================
  -- __rustlib backend resolution
  -- ============================================================

  describe("__rustlib backend", function()
    it("uses injected json directly", function()
      local mock_json = {
        decode = function(s) return { injected = true } end,
        encode = function(t) return "{}" end,
      }
      local s = reload_std_with_rustlib({ json = mock_json })
      assert.equal(mock_json, s.json)
    end)

    it("uses injected fs directly (no check_path wrapper)", function()
      local mock_fs = {
        read_file   = function(p) return "trusted" end,
        file_exists = function(p) return true end,
      }
      local s = reload_std_with_rustlib({ fs = mock_fs })
      assert.equal(mock_fs, s.fs)
    end)

    it("uses injected time", function()
      local time_fn = function() return 99999.0 end
      local s = reload_std_with_rustlib({ time = time_fn })
      assert.equal(time_fn, s.time)
    end)

    it("uses injected http", function()
      local mock_http = { get = function() end }
      local s = reload_std_with_rustlib({ http = mock_http })
      assert.equal(mock_http, s.http)
    end)

    it("uses injected exec", function()
      local mock_exec = { run = function() end }
      local s = reload_std_with_rustlib({ exec = mock_exec })
      assert.equal(mock_exec, s.exec)
    end)

    it("does not load senl modules when __rustlib is present", function()
      -- If senl.json were loaded, senl detection would be skipped due to
      -- `if not injected then` guard. Verify __rustlib takes full priority.
      local mock_json = { decode = function() return "RUSTLIB" end, encode = tostring }
      local s = reload_std_with_rustlib({ json = mock_json })
      assert.equal("RUSTLIB", s.json.decode("x"))
    end)
  end)
end)
