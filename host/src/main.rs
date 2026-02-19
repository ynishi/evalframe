use senl::SenlApp;
use std::{env, path::PathBuf, process};

// ============================================================
// CLI entry point (evalframe_cli.lua)
// ============================================================

const CLI_LUA: &str = include_str!("../lua/evalframe_cli.lua");

// ============================================================
// Embedded evalframe Lua modules
//
// All 25 modules are compiled into the binary via include_str!.
// In embedded mode (default), these are registered as preloaded
// modules so `require("evalframe")` works without filesystem access.
// ============================================================

const EVALFRAME_FILES: &[(&str, &str)] = &[
    ("init.lua", include_str!("../../evalframe/init.lua")),
    ("std.lua", include_str!("../../evalframe/std.lua")),
    ("variants.lua", include_str!("../../evalframe/variants.lua")),
    (
        "eval/init.lua",
        include_str!("../../evalframe/eval/init.lua"),
    ),
    (
        "eval/loader.lua",
        include_str!("../../evalframe/eval/loader.lua"),
    ),
    (
        "eval/report.lua",
        include_str!("../../evalframe/eval/report.lua"),
    ),
    (
        "eval/runner.lua",
        include_str!("../../evalframe/eval/runner.lua"),
    ),
    (
        "eval/stats.lua",
        include_str!("../../evalframe/eval/stats.lua"),
    ),
    (
        "model/binding.lua",
        include_str!("../../evalframe/model/binding.lua"),
    ),
    (
        "model/case.lua",
        include_str!("../../evalframe/model/case.lua"),
    ),
    (
        "model/grader.lua",
        include_str!("../../evalframe/model/grader.lua"),
    ),
    (
        "model/scorer.lua",
        include_str!("../../evalframe/model/scorer.lua"),
    ),
    (
        "presets/graders.lua",
        include_str!("../../evalframe/presets/graders.lua"),
    ),
    (
        "presets/llm_graders.lua",
        include_str!("../../evalframe/presets/llm_graders.lua"),
    ),
    (
        "presets/scorers.lua",
        include_str!("../../evalframe/presets/scorers.lua"),
    ),
    (
        "providers/claude_cli.lua",
        include_str!("../../evalframe/providers/claude_cli.lua"),
    ),
    (
        "providers/mock.lua",
        include_str!("../../evalframe/providers/mock.lua"),
    ),
    (
        "swarm/init.lua",
        include_str!("../../evalframe/swarm/init.lua"),
    ),
    (
        "swarm/actions.lua",
        include_str!("../../evalframe/swarm/actions.lua"),
    ),
    (
        "swarm/analysis.lua",
        include_str!("../../evalframe/swarm/analysis.lua"),
    ),
    (
        "swarm/config.lua",
        include_str!("../../evalframe/swarm/config.lua"),
    ),
    (
        "swarm/env.lua",
        include_str!("../../evalframe/swarm/env.lua"),
    ),
    (
        "swarm/graders.lua",
        include_str!("../../evalframe/swarm/graders.lua"),
    ),
    (
        "swarm/provider.lua",
        include_str!("../../evalframe/swarm/provider.lua"),
    ),
    (
        "swarm/trace.lua",
        include_str!("../../evalframe/swarm/trace.lua"),
    ),
];

fn main() {
    let exit_code = match run() {
        Ok(code) => code,
        Err(e) => {
            eprintln!("evalframe: {e}");
            1
        }
    };
    process::exit(exit_code);
}

/// Build and run the evalframe CLI app.
///
/// Dual-mode Lua loading:
///   - **FS mode**: When `EVALFRAME_LUA_DIR` is set (or auto-detected),
///     Lua modules are loaded from the filesystem via `with_lua_search_path`.
///     Ideal for development — edit Lua files without recompiling.
///   - **Embedded mode** (default): All Lua modules are compiled into
///     the binary via `with_preload_dir`. Zero external file dependencies.
fn run() -> senl::Result<i32> {
    let app = SenlApp::from_source("evalframe", CLI_LUA);

    let app = if let Some(lua_dir) = find_lua_dir() {
        // FS mode: load evalframe modules from disk
        app.with_lua_search_path(lua_dir.to_string_lossy().to_string())
    } else {
        // Embedded mode: all modules compiled into the binary
        app.with_preload_dir("evalframe", EVALFRAME_FILES)
    };

    app.run()
}

/// Find the evalframe Lua modules directory for FS mode.
///
/// Returns `Some(path)` when FS mode should be used, `None` for embedded mode.
///
/// Search order:
/// 1. `EVALFRAME_LUA_DIR` env var (explicit override)
/// 2. `./evalframe/` relative to CWD (project root execution)
/// 3. `../evalframe/` relative to the binary (installed layout)
///
/// If none found, falls back to embedded mode (returns `None`).
fn find_lua_dir() -> Option<PathBuf> {
    // 1. Explicit env var — always use FS mode when set
    if let Ok(dir) = env::var("EVALFRAME_LUA_DIR") {
        let p = PathBuf::from(&dir);
        if p.is_dir() {
            return Some(p.canonicalize().unwrap_or(p));
        }
        // Env var set but invalid path: warn and fall through to embedded
        eprintln!(
            "evalframe: EVALFRAME_LUA_DIR={dir} is not a valid directory, using embedded modules"
        );
    }

    // 2. Relative to CWD (typical: running from project root)
    let cwd_candidate = PathBuf::from("evalframe");
    if cwd_candidate.is_dir() {
        // Check for init.lua to confirm it's the right directory
        if cwd_candidate.join("init.lua").exists() {
            return Some(cwd_candidate.canonicalize().unwrap_or(cwd_candidate));
        }
    }

    // 3. Relative to binary (installed: bin/evalframe + ../evalframe/)
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            let candidate = parent.join("../evalframe");
            if candidate.is_dir() && candidate.join("init.lua").exists() {
                return Some(candidate.canonicalize().unwrap_or(candidate));
            }
        }
    }

    // No FS directory found → use embedded mode
    None
}
