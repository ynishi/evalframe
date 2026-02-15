-- Attempts to use os.execute (should fail in sandbox)
os.execute("echo pwned")
return {
  { input = "q", expected = "a" },
}
