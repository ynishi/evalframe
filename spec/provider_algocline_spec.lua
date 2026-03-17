local h = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect

describe("Providers — algocline", function()

  -- ============================================================
  -- alc global not present (normal lspec environment)
  -- ============================================================

  describe("llm()", function()
    it("errors when alc global is absent", function()
      h.assert_error_contains(function()
        local algocline = require("evalframe.providers.algocline")
        algocline.llm()
      end, "requires algocline VM")
    end)
  end)

  describe("strategy provider", function()
    it("errors when alc global is absent", function()
      h.assert_error_contains(function()
        local algocline = require("evalframe.providers.algocline")
        algocline { strategy = "reflect" }
      end, "requires algocline VM")
    end)

    it("errors when strategy is missing", function()
      h.assert_error_contains(function()
        local algocline = require("evalframe.providers.algocline")
        algocline {}
      end, "'strategy' must be a string")
    end)

    it("errors when strategy is non-string", function()
      h.assert_error_contains(function()
        local algocline = require("evalframe.providers.algocline")
        algocline { strategy = 42 }
      end, "'strategy' must be a string")
    end)
  end)

  -- ============================================================
  -- With mock alc global
  -- ============================================================

  describe("llm() with mock alc", function()
    local _orig_alc

    lust.before(function()
      _orig_alc = rawget(_G, "alc")
    end)

    lust.after(function()
      rawset(_G, "alc", _orig_alc)
      -- Force re-require so next describe block gets clean state
      package.loaded["evalframe.providers.algocline"] = nil
    end)

    it("returns provider function when alc is present", function()
      rawset(_G, "alc", {
        llm = function(input) return "mock: " .. input end,
      })
      package.loaded["evalframe.providers.algocline"] = nil
      local algocline = require("evalframe.providers.algocline")

      local provider = algocline.llm()
      expect(type(provider)).to.equal("function")
    end)

    it("returns response table with correct fields", function()
      rawset(_G, "alc", {
        llm = function(input) return "echo: " .. input end,
      })
      package.loaded["evalframe.providers.algocline"] = nil
      local algocline = require("evalframe.providers.algocline")

      local provider = algocline.llm()
      local resp = provider("hello")

      expect(resp.text).to.equal("echo: hello")
      expect(resp.model).to.equal("alc_llm")
      expect(type(resp.latency_ms)).to.equal("number")
      expect(resp.latency_ms >= 0).to.equal(true)
    end)

    it("coerces non-string return to string", function()
      rawset(_G, "alc", {
        llm = function(_) return 42 end,
      })
      package.loaded["evalframe.providers.algocline"] = nil
      local algocline = require("evalframe.providers.algocline")

      local provider = algocline.llm()
      local resp = provider("test")

      expect(resp.text).to.equal("42")
    end)

    it("coerces nil return to string", function()
      rawset(_G, "alc", {
        llm = function(_) return nil end,
      })
      package.loaded["evalframe.providers.algocline"] = nil
      local algocline = require("evalframe.providers.algocline")

      local provider = algocline.llm()
      local resp = provider("test")

      expect(resp.text).to.equal("nil")
    end)
  end)
end)
