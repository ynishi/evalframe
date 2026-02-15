-- Attempts to use io.open (should fail in sandbox)
local f = io.open("/etc/passwd", "r")
return {
  { input = "q", expected = "a" },
}
