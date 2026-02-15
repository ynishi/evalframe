-- Attempts to use require (should fail in sandbox)
local os = require("os")
os.execute("echo pwned")
return {
  { input = "q", expected = "a" },
}
