local loader = require("evalframe.eval.loader")
local case   = require("evalframe.model.case")
local h      = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("Loader", function()

  -- ============================================================
  -- Normal: valid case file
  -- ============================================================

  describe("load_file", function()
    it("loads valid case file", function()
      local cases = loader.load_file("spec/fixtures/valid_cases.lua")
      expect(#cases).to.equal(2)
      expect(case.is_case(cases[1])).to.equal(true)
      expect(cases[1].input).to.equal("2+2?")
      expect(cases[1].expected).to.equal({ "4" })
    end)

    it("preserves tags from loaded cases", function()
      local cases = loader.load_file("spec/fixtures/valid_cases.lua")
      expect(cases[1].tags).to.equal({ "math" })
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
      end, "No such file")
    end)

    it("errors on file returning non-table", function()
      h.assert_error_contains(function()
        loader.load_file("spec/fixtures/returns_string.lua")
      end, "must return a table")
    end)
  end)
end)
