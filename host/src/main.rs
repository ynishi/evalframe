use clap::{Parser, Subcommand};
use mlua::prelude::*;
use mlua_pkg::resolvers::{FsResolver, MemoryResolver, NativeResolver};
use mlua_pkg::Registry;
use std::{path::PathBuf, process};

// ============================================================
// CLI definition — Host's responsibility (compile-time verified)
// ============================================================

#[derive(Parser)]
#[command(name = "evalframe", about = "LLM evaluation framework", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Execute an evaluation suite
    Run {
        /// Path to the suite Lua file
        suite: PathBuf,

        /// Output results as JSON
        #[arg(short = 'j', long)]
        json: bool,

        /// Write results to file
        #[arg(short = 'o', long)]
        output: Option<PathBuf>,
    },

    /// Run spec files on the mlua VM using lspec
    Test {
        /// Spec files or directories to run
        #[arg(default_value = "spec")]
        paths: Vec<PathBuf>,

        /// Only run specs matching this pattern
        #[arg(short = 'f', long)]
        filter: Option<String>,
    },
}

// ============================================================
// Embedded evalframe Lua modules
// ============================================================

const EVALFRAME_MODULES: &[(&str, &str)] = &[
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
        "providers/algocline.lua",
        include_str!("../../evalframe/providers/algocline.lua"),
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

fn run() -> Result<i32, Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    match cli.command {
        Command::Run {
            suite,
            json,
            output,
        } => run_suite(&suite, json, output.as_deref()),
        Command::Test { paths, filter } => run_spec_tests(&paths, filter.as_deref()),
    }
}

// ============================================================
// Test runner — execute spec files on mlua VM with lspec
// ============================================================

/// Collect spec files from paths (files or directories).
/// Recursively finds `*_spec.lua` files in directories.
fn collect_spec_files(paths: &[PathBuf]) -> Result<Vec<PathBuf>, Box<dyn std::error::Error>> {
    let mut specs = Vec::new();
    for path in paths {
        if path.is_file() {
            specs.push(path.clone());
        } else if path.is_dir() {
            collect_specs_recursive(path, &mut specs)?;
        } else {
            return Err(format!("{} is not a file or directory", path.display()).into());
        }
    }
    specs.sort();
    Ok(specs)
}

fn collect_specs_recursive(
    dir: &std::path::Path,
    out: &mut Vec<PathBuf>,
) -> Result<(), Box<dyn std::error::Error>> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_specs_recursive(&path, out)?;
        } else if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if name.ends_with("_spec.lua") {
                out.push(path);
            }
        }
    }
    Ok(())
}

/// Run spec files on the mlua VM using lspec.
///
/// Each spec file runs in a fresh VM with:
///   - mlua-batteries `std` global
///   - evalframe modules available via require()
///   - lspec `lust` global (describe/it/expect)
///   - spec helper available via require("spec.spec_helper")
fn run_spec_tests(
    paths: &[PathBuf],
    filter: Option<&str>,
) -> Result<i32, Box<dyn std::error::Error>> {
    let spec_files = collect_spec_files(paths)?;
    if spec_files.is_empty() {
        eprintln!("evalframe test: no spec files found");
        return Ok(1);
    }

    let start = std::time::Instant::now();
    let mut total_passed = 0usize;
    let mut total_failed = 0usize;
    let mut failed_details: Vec<(String, Vec<mlua_lspec::TestResult>)> = Vec::new();

    for spec_path in &spec_files {
        // Use a dummy path for create_lua — spec's parent provides co-located requires
        let lua = create_lua(spec_path)?;

        // Register lspec framework (lust global)
        mlua_lspec::register(&lua).map_err(|e| format!("Failed to register lspec: {e}"))?;

        // Load and run the spec file
        let source = std::fs::read_to_string(spec_path)
            .map_err(|e| format!("Failed to read {}: {e}", spec_path.display()))?;

        if let Err(e) = lua
            .load(source.as_str())
            .set_name(spec_path.to_string_lossy().as_ref())
            .exec()
        {
            eprintln!("  ERROR in {}: {e}", spec_path.display());
            total_failed += 1;
            continue;
        }

        // Collect results
        let summary = mlua_lspec::collect_results(&lua).map_err(|e| {
            format!(
                "Failed to collect results from {}: {e}",
                spec_path.display()
            )
        })?;

        total_passed += summary.passed;
        total_failed += summary.failed;

        // Report per-file status
        let status = if summary.failed == 0 { "PASS" } else { "FAIL" };
        let spec_name = spec_path
            .strip_prefix(std::env::current_dir().unwrap_or_default())
            .unwrap_or(spec_path)
            .display();
        eprintln!(
            "  {status} {spec_name} ({}/{})",
            summary.passed, summary.total
        );

        // Collect failures for detail report
        if summary.failed > 0 {
            let failures: Vec<_> = summary.tests.into_iter().filter(|t| !t.passed).collect();
            if let Some(f) = filter {
                let filtered: Vec<_> = failures
                    .into_iter()
                    .filter(|t| t.name.contains(f) || t.suite.contains(f))
                    .collect();
                if !filtered.is_empty() {
                    failed_details.push((spec_name.to_string(), filtered));
                }
            } else {
                failed_details.push((spec_name.to_string(), failures));
            }
        }
    }

    let elapsed = start.elapsed().as_secs_f64();

    // Summary
    eprintln!();
    if !failed_details.is_empty() {
        eprintln!("Failures:");
        for (file, failures) in &failed_details {
            for f in failures {
                eprintln!("  {} > {} > {}", file, f.suite, f.name);
                if let Some(ref err) = f.error {
                    eprintln!("    {err}");
                }
            }
        }
        eprintln!();
    }

    let total = total_passed + total_failed;
    eprintln!(
        "{} specs, {} passed, {} failed ({:.2}s)",
        total, total_passed, total_failed, elapsed
    );

    Ok(if total_failed > 0 { 1 } else { 0 })
}

// ============================================================
// Suite runner
// ============================================================

/// Execute an evaluation suite.
///
/// Host/Script boundary:
///   Host (this function): VM creation, stdlib injection, CLI args, output formatting
///   Script (suite .lua):  evalframe DSL, evaluation logic
fn run_suite(
    suite_path: &std::path::Path,
    json_output: bool,
    output_path: Option<&std::path::Path>,
) -> Result<i32, Box<dyn std::error::Error>> {
    let lua = create_lua(suite_path)?;

    // Load and execute the suite file
    let suite_source = std::fs::read_to_string(suite_path)
        .map_err(|e| format!("Failed to read {}: {e}", suite_path.display()))?;

    // Strip shebang line (#!/...) — Lua's loadfile handles this, but
    // mlua's load() does not.
    let source = if suite_source.starts_with("#!") {
        suite_source
            .find('\n')
            .map(|i| &suite_source[i + 1..])
            .unwrap_or("")
    } else {
        &suite_source
    };

    let start = std::time::Instant::now();

    let result: LuaValue = lua
        .load(source)
        .set_name(suite_path.to_string_lossy().as_ref())
        .eval()
        .map_err(|e| format!("{e}"))?;

    let elapsed = start.elapsed().as_secs_f64();

    // Format and output results — Host's responsibility
    if json_output {
        match result {
            LuaValue::Table(ref tbl) => {
                let json_str = table_to_json(&lua, tbl)?;
                if let Some(path) = output_path {
                    std::fs::write(path, &json_str)?;
                    eprintln!("Results written to {} ({:.2}s)", path.display(), elapsed);
                } else {
                    println!("{json_str}");
                }
                return Ok(0);
            }
            _ => {
                eprintln!(
                    "evalframe: --json requested but suite returned {}, not a table",
                    lua_value_type_name(&result)
                );
                return Ok(1);
            }
        }
    }

    // Default output: print the result as text
    let text = lua_value_to_string(&result);
    if let Some(path) = output_path {
        std::fs::write(path, &text)?;
        eprintln!("Output written to {} ({:.2}s)", path.display(), elapsed);
    } else if !text.is_empty() {
        println!("{text}");
    }

    Ok(0)
}

/// Create a Lua VM with mlua-pkg Registry for module resolution.
///
/// Resolution chain (priority order):
///   1. NativeResolver — batteries stdlib modules (std.* global)
///   2. MemoryResolver or FsResolver — evalframe modules (embedded or FS)
///   3. FsResolver — suite's directory (co-located modules)
///   4. FsResolver — CWD (project root)
///
/// Boundary contract:
///   - `std` global: mlua-batteries (json, fs, time, http, env, path, string, validate)
///   - `evalframe.*` modules: available via require()
///   - Suite-local modules: available via require()
fn create_lua(suite_path: &std::path::Path) -> Result<Lua, Box<dyn std::error::Error>> {
    let lua = Lua::new();

    // ① Inject stdlib as global — batteries registers `std` global table
    mlua_batteries::register_all(&lua, "std")?;

    // ② Build Registry for require() resolution
    let mut reg = Registry::new();

    // Resolver 1: batteries modules via NativeResolver
    // Makes batteries individually require()-able (e.g., require("@std/json"))
    let mut native = NativeResolver::new();
    for (name, factory) in mlua_batteries::module_entries() {
        native = native.add(format!("@std/{name}"), move |lua| {
            factory(lua).map(LuaValue::Table)
        });
    }
    reg.add(native);

    // Resolver 2: evalframe modules (embedded or FS)
    let mode = detect_lua_mode(suite_path);
    match mode {
        LuaMode::Filesystem(ref dir) => match FsResolver::new(dir) {
            Ok(resolver) => {
                reg.add(resolver);
            }
            Err(e) => {
                eprintln!(
                    "evalframe: FS resolver for {} failed: {e}, falling back to embedded",
                    dir.display()
                );
                reg.add(build_evalframe_memory_resolver());
            }
        },
        LuaMode::Embedded => {
            reg.add(build_evalframe_memory_resolver());
        }
    }

    // Resolver 3: suite's directory (co-located modules)
    if let Some(parent) = suite_path.parent() {
        if !parent.as_os_str().is_empty() {
            if let Ok(resolver) = FsResolver::new(parent) {
                reg.add(resolver);
            }
        }
    }

    // Resolver 4: CWD (for require("evalframe") from project root)
    if let Ok(cwd) = std::env::current_dir() {
        if let Ok(resolver) = FsResolver::new(&cwd) {
            reg.add(resolver);
        }
    }

    reg.install(&lua)?;

    Ok(lua)
}

/// Build a MemoryResolver for embedded evalframe modules.
fn build_evalframe_memory_resolver() -> MemoryResolver {
    let mut mem = MemoryResolver::new();
    for (path, source) in EVALFRAME_MODULES {
        mem = mem.add(path_to_module_name("evalframe", path), *source);
    }
    mem
}

// ============================================================
// Lua VM helpers
// ============================================================

enum LuaMode {
    Filesystem(PathBuf),
    Embedded,
}

/// Detect whether to load evalframe modules from filesystem or embedded.
///
/// Search order:
/// 1. EVALFRAME_LUA_DIR env var
/// 2. ./evalframe/ relative to CWD
/// 3. ../evalframe/ relative to binary
/// 4. Embedded (fallback)
fn detect_lua_mode(suite_path: &std::path::Path) -> LuaMode {
    // Env var override
    if let Ok(dir) = std::env::var("EVALFRAME_LUA_DIR") {
        let p = PathBuf::from(&dir);
        if p.is_dir() {
            return LuaMode::Filesystem(p.canonicalize().unwrap_or(p));
        }
        eprintln!(
            "evalframe: EVALFRAME_LUA_DIR={dir} is not a valid directory, using embedded modules"
        );
    }

    // Relative to CWD
    let cwd_candidate = PathBuf::from("evalframe");
    if cwd_candidate.is_dir() && cwd_candidate.join("init.lua").exists() {
        return LuaMode::Filesystem(cwd_candidate.canonicalize().unwrap_or(cwd_candidate));
    }

    // Relative to binary
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let candidate = parent.join("../evalframe");
            if candidate.is_dir() && candidate.join("init.lua").exists() {
                return LuaMode::Filesystem(candidate.canonicalize().unwrap_or(candidate));
            }
        }
    }

    // Suite's parent directory (for co-located evalframe/)
    if let Some(parent) = suite_path.parent() {
        let candidate = parent.join("evalframe");
        if candidate.is_dir() && candidate.join("init.lua").exists() {
            return LuaMode::Filesystem(candidate.canonicalize().unwrap_or(candidate));
        }
    }

    LuaMode::Embedded
}

/// Register Lua source files as preloaded modules (test-only).
///
/// Path mapping: "init.lua" → base, "sub/init.lua" → base.sub, "sub/mod.lua" → base.sub.mod
#[cfg(test)]
fn register_preloads(lua: &Lua, base: &str, files: &[(&str, &str)]) -> LuaResult<()> {
    let preload: LuaTable = lua
        .globals()
        .get::<LuaTable>("package")?
        .get::<LuaTable>("preload")?;

    for (path, source) in files {
        let module_name = path_to_module_name(base, path);
        let chunk = lua.load(*source).set_name(&module_name).into_function()?;
        preload.set(module_name.as_str(), chunk)?;
    }

    Ok(())
}

/// Convert file path to Lua module name.
fn path_to_module_name(base: &str, path: &str) -> String {
    let stripped = path
        .strip_suffix(".lua")
        .unwrap_or(path)
        .replace(['/', '\\'], ".");

    match stripped.strip_suffix(".init") {
        Some("") | None if stripped == "init" => base.to_string(),
        Some(prefix) => format!("{base}.{prefix}"),
        None => format!("{base}.{stripped}"),
    }
}

/// Convert a Lua table to JSON string using batteries' json module.
fn table_to_json(lua: &Lua, tbl: &LuaTable) -> Result<String, Box<dyn std::error::Error>> {
    let std_global: LuaTable = lua.globals().get::<LuaTable>("std")?;
    let json_mod: LuaTable = std_global.get::<LuaTable>("json")?;
    let encode: LuaFunction = json_mod.get::<LuaFunction>("encode")?;
    let result: String = encode.call(LuaValue::Table(tbl.clone()))?;
    Ok(result)
}

/// Convert a LuaValue to string for output.
fn lua_value_to_string(value: &LuaValue) -> String {
    match value {
        LuaValue::String(s) => s.to_string_lossy().to_string(),
        LuaValue::Integer(n) => n.to_string(),
        LuaValue::Number(n) => format!("{n}"),
        LuaValue::Boolean(b) => b.to_string(),
        LuaValue::Nil => String::new(),
        other => format!("{other:?}"),
    }
}

/// Return Lua type name for diagnostic messages.
fn lua_value_type_name(value: &LuaValue) -> &'static str {
    match value {
        LuaValue::Nil => "nil",
        LuaValue::Boolean(_) => "boolean",
        LuaValue::Integer(_) => "integer",
        LuaValue::Number(_) => "number",
        LuaValue::String(_) => "string",
        LuaValue::Table(_) => "table",
        LuaValue::Function(_) => "function",
        _ => "userdata",
    }
}

// ============================================================
// Tests
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_to_module_name_init() {
        assert_eq!(path_to_module_name("ef", "init.lua"), "ef");
    }

    #[test]
    fn path_to_module_name_flat() {
        assert_eq!(path_to_module_name("ef", "std.lua"), "ef.std");
    }

    #[test]
    fn path_to_module_name_nested_init() {
        assert_eq!(path_to_module_name("ef", "eval/init.lua"), "ef.eval");
    }

    #[test]
    fn path_to_module_name_nested_file() {
        assert_eq!(path_to_module_name("ef", "eval/stats.lua"), "ef.eval.stats");
    }

    #[test]
    fn path_to_module_name_deep() {
        assert_eq!(
            path_to_module_name("ef", "model/nested/deep.lua"),
            "ef.model.nested.deep"
        );
    }

    #[test]
    fn lua_vm_creates_with_batteries() {
        let lua = Lua::new();
        mlua_batteries::register_all(&lua, "std").unwrap();

        let result: String = lua.load(r#"return type(std.json.encode)"#).eval().unwrap();
        assert_eq!(result, "function");
    }

    #[test]
    fn lua_vm_creates_with_batteries_time() {
        let lua = Lua::new();
        mlua_batteries::register_all(&lua, "std").unwrap();

        let result: String = lua.load(r#"return type(std.time.now)"#).eval().unwrap();
        assert_eq!(result, "function");
    }

    #[test]
    fn preload_registration_works() {
        let lua = Lua::new();
        let files: &[(&str, &str)] = &[
            ("init.lua", "return { name = 'test' }"),
            ("sub.lua", "return { val = 42 }"),
        ];
        register_preloads(&lua, "mypkg", files).unwrap();

        let name: String = lua.load(r#"return require("mypkg").name"#).eval().unwrap();
        assert_eq!(name, "test");

        let val: i32 = lua
            .load(r#"return require("mypkg.sub").val"#)
            .eval()
            .unwrap();
        assert_eq!(val, 42);
    }
}
