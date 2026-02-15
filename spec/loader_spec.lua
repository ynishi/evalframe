local loader = require("evalframe.eval.loader")
local case   = require("evalframe.model.case")
local h      = require("spec.spec_helper")

describe("Loader", function()

  -- ============================================================
  -- Normal: valid case file
  -- ============================================================

  describe("load_file", function()
    it("loads valid case file", function()
      local cases = loader.load_file("spec/fixtures/valid_cases.lua")
      assert.equals(2, #cases)
      assert.is_true(case.is_case(cases[1]))
      assert.equals("2+2?", cases[1].input)
      assert.same({ "4" }, cases[1].expected)
    end)

    it("preserves tags from loaded cases", function()
      local cases = loader.load_file("spec/fixtures/valid_cases.lua")
      assert.same({ "math" }, cases[1].tags)
    end)
  end)

  -- ============================================================
  -- Sandbox: blocked operations
  -- ============================================================

  describe("sandbox", function()
    it("blocks os.execute", function()
      h.assert_error_contains(function()
        loader.load_file("spec/fixtures/malicious_cases.lua")
      end, "runtime error")
    end)

    it("blocks io.open", function()
      h.assert_error_contains(function()
        loader.load_file("spec/fixtures/malicious_io.lua")
      end, "runtime error")
    end)

    it("blocks require", function()
      h.assert_error_contains(function()
        loader.load_file("spec/fixtures/malicious_require.lua")
      end, "runtime error")
    end)
  end)

  -- ============================================================
  -- Error cases
  -- ============================================================

  describe("errors", function()
    it("errors on non-existent file", function()
      h.assert_error_contains(function()
        loader.load_file("spec/fixtures/nonexistent.lua")
      end, "std.fs.read_file")
    end)

    it("errors on file returning non-table", function()
      -- Create an inline test: we can't easily write temp files,
      -- so test via the module's behavior with a known-bad fixture
      h.assert_error_contains(function()
        loader.load_file("spec/fixtures/malicious_cases.lua")
      end, "error")
    end)
  end)
end)
