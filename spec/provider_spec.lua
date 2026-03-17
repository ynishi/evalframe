local mock      = require("evalframe.providers.mock")
local claude    = require("evalframe.providers.claude_cli")
local ef        = require("evalframe")
local h         = require("spec.spec_helper")

local describe, it, expect = lust.describe, lust.it, lust.expect
describe("Providers", function()

  -- ============================================================
  -- Mock provider
  -- ============================================================

  describe("mock", function()
    describe("static", function()
      it("always returns same text", function()
        local p = mock.static("hello")
        local r = p("anything")
        expect(r.text).to.equal("hello")
        expect(r.model).to.equal("mock")
      end)
    end)

    describe("map", function()
      it("returns exact match", function()
        local p = mock.map({ ["2+2"] = "4" })
        expect(p("2+2").text).to.equal("4")
      end)

      it("returns partial match", function()
        local p = mock.map({ ["2+2"] = "4" })
        expect(p("What is 2+2?").text).to.equal("4")
      end)

      it("returns empty on no match", function()
        local p = mock.map({ ["2+2"] = "4" })
        expect(p("hello").text).to.equal("")
      end)

      it("returns longest partial match when multiple keys match", function()
        local p = mock.map({
          ["2+2"] = "short",
          ["What is 2+2"] = "long",
        })
        expect(p("What is 2+2?").text).to.equal("long")
      end)
    end)

    describe("fn", function()
      it("wraps custom function", function()
        local p = mock.fn(function(input)
          return "Echo: " .. input
        end)
        expect(p("hi").text).to.equal("Echo: hi")
      end)
    end)

    describe("recording", function()
      it("records calls and cycles responses", function()
        local p, log = mock.recording({ "a", "b" })
        p("first")
        p("second")
        p("third")
        expect(#log.calls).to.equal(3)
        expect(log.calls[1]).to.equal("first")
        expect(log.calls[2]).to.equal("second")
        expect(log.calls[3]).to.equal("third")
      end)

      it("cycles through responses", function()
        local p, _ = mock.recording({ "a", "b" })
        expect(p("x").text).to.equal("a")
        expect(p("x").text).to.equal("b")
        expect(p("x").text).to.equal("a")  -- cycles
      end)

      it("rejects empty responses list", function()
        h.assert_error_contains(function()
          mock.recording({})
        end, "non-empty list")
      end)

      it("rejects nil responses", function()
        h.assert_error_contains(function()
          mock.recording(nil)
        end, "non-empty list")
      end)
    end)
  end)

  -- ============================================================
  -- Provider integration with suite
  -- ============================================================

  describe("integration with suite", function()
    it("mock.static works in suite", function()
      local s = ef.suite "mock_test" {
        provider = mock.static("4"),
        ef.bind { ef.graders.exact_match },
        cases = {
          ef.case { input = "2+2?", expected = "4" },
        },
      }
      local report = s:run()
      expect(report.aggregated.passed).to.equal(1)
    end)

    it("mock.map works in suite", function()
      local s = ef.suite "map_test" {
        provider = mock.map({
          ["What is 2+2?"] = "4",
          ["What is 3*3?"] = "9",
        }),
        ef.bind { ef.graders.exact_match },
        cases = {
          ef.case { input = "What is 2+2?", expected = "4" },
          ef.case { input = "What is 3*3?", expected = "9" },
        },
      }
      local report = s:run()
      expect(report.aggregated.passed).to.equal(2)
    end)

    it("ef.providers.mock is accessible", function()
      local p = ef.providers.mock.static("test")
      expect(p).to.be.a("function")
      expect(p("x").text).to.equal("test")
    end)
  end)

  -- ============================================================
  -- claude_cli opts validation
  -- ============================================================

  describe("claude_cli validation", function()
    it("rejects non-string model", function()
      h.assert_error_contains(function()
        claude { model = 123 }
      end, "'model' must be string")
    end)

    it("rejects non-string system", function()
      h.assert_error_contains(function()
        claude { system = true }
      end, "'system' must be string")
    end)

    it("rejects non-number max_tokens", function()
      h.assert_error_contains(function()
        claude { max_tokens = "many" }
      end, "'max_tokens' must be number")
    end)

    it("rejects non-string cwd", function()
      h.assert_error_contains(function()
        claude { cwd = 42 }
      end, "'cwd' must be string")
    end)

    it("accepts valid opts", function()
      h.assert_no_error(function()
        claude { model = "haiku", system = "Be concise", max_tokens = 100 }
      end)
    end)

    it("accepts empty opts", function()
      h.assert_no_error(function()
        claude()
      end)
    end)
  end)
end)
