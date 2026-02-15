local mock      = require("evalframe.providers.mock")
local claude    = require("evalframe.providers.claude_cli")
local ef        = require("evalframe")
local h         = require("spec.spec_helper")

describe("Providers", function()

  -- ============================================================
  -- Mock provider
  -- ============================================================

  describe("mock", function()
    describe("static", function()
      it("always returns same text", function()
        local p = mock.static("hello")
        local r = p("anything")
        assert.equals("hello", r.text)
        assert.equals("mock", r.model)
      end)
    end)

    describe("map", function()
      it("returns exact match", function()
        local p = mock.map({ ["2+2"] = "4" })
        assert.equals("4", p("2+2").text)
      end)

      it("returns partial match", function()
        local p = mock.map({ ["2+2"] = "4" })
        assert.equals("4", p("What is 2+2?").text)
      end)

      it("returns empty on no match", function()
        local p = mock.map({ ["2+2"] = "4" })
        assert.equals("", p("hello").text)
      end)

      it("returns longest partial match when multiple keys match", function()
        local p = mock.map({
          ["2+2"] = "short",
          ["What is 2+2"] = "long",
        })
        assert.equals("long", p("What is 2+2?").text)
      end)
    end)

    describe("fn", function()
      it("wraps custom function", function()
        local p = mock.fn(function(input)
          return "Echo: " .. input
        end)
        assert.equals("Echo: hi", p("hi").text)
      end)
    end)

    describe("recording", function()
      it("records calls and cycles responses", function()
        local p, log = mock.recording({ "a", "b" })
        p("first")
        p("second")
        p("third")
        assert.equals(3, #log.calls)
        assert.equals("first", log.calls[1])
        assert.equals("second", log.calls[2])
        assert.equals("third", log.calls[3])
      end)

      it("cycles through responses", function()
        local p, _ = mock.recording({ "a", "b" })
        assert.equals("a", p("x").text)
        assert.equals("b", p("x").text)
        assert.equals("a", p("x").text)  -- cycles
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
      assert.equals(1, report.aggregated.passed)
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
      assert.equals(2, report.aggregated.passed)
    end)

    it("ef.providers.mock is accessible", function()
      local p = ef.providers.mock.static("test")
      assert.is_function(p)
      assert.equals("test", p("x").text)
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
