local std = require("evalframe.std")
local h   = require("spec.spec_helper")

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
end)
