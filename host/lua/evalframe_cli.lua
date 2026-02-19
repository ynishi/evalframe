-- evalframe CLI definition (senl app)
--
-- Executed by the evalframe Rust host via senl.
-- Defines subcommands: run
--
-- Usage:
--   evalframe run suite.lua
--   evalframe run examples/swarm_eval.lua --json
--   evalframe run suite.lua --output results.json

local sen  = require("lua_sen")
local time = require("senl.time")

-- ============================================================
-- run: execute an evaluation suite
-- ============================================================

local function run_handler(ctx)
  local suite_path = ctx.args.suite

  -- Add suite file's directory to package.path
  -- so the suite can require local modules.
  local dir = suite_path:match("(.*/)")
  if dir then
    package.path = dir .. "?.lua;" .. dir .. "?/init.lua;" .. package.path
  end

  -- Also add CWD patterns (for `require("evalframe")` when running from project root)
  package.path = "?.lua;?/init.lua;" .. package.path

  -- Security boundary: loadfile executes user-provided Lua without sandboxing.
  -- Intentional — the CLI runs as the invoking user and trusts the suite file.
  -- Case files loaded *within* suites are sandboxed by evalframe.eval.loader.
  local chunk, load_err = loadfile(suite_path)
  if not chunk then
    return sen.err("Failed to load " .. suite_path .. ": " .. tostring(load_err))
  end

  local elapsed, ok, result = time.measure(function()
    return pcall(chunk)
  end)

  if not ok then
    return sen.err(tostring(result))
  end

  -- If --json flag requested, attempt JSON output of the suite result
  if ctx.args.json and type(result) == "table" then
    local json_ok, json = pcall(require, "senl.json")
    if json_ok then
      local encoded = json.encode(result)
      if ctx.args.output then
        local fs = require("senl.fs")
        fs.write(ctx.args.output, encoded)
        return sen.ok(string.format("Results written to %s (%.2fs)", ctx.args.output, elapsed))
      end
      return sen.ok(encoded)
    end
  end

  -- If --output specified without --json, write raw result
  if ctx.args.output and type(result) == "string" then
    local fs = require("senl.fs")
    fs.write(ctx.args.output, result)
    return sen.ok(string.format("Output written to %s (%.2fs)", ctx.args.output, elapsed))
  end

  return sen.silent()
end

-- ============================================================
-- CLI definition
-- ============================================================

local app = sen.app("evalframe", "LLM evaluation framework")
  :version("0.2.0")
  :command("run", "Execute an evaluation suite")
    :arg("suite", "Path to the suite Lua file")
    :flag("j", "json", "Output results as JSON")
    :option("o", "output", "Write results to file")
    :done()

app:route("run", run_handler)

return app:build()
