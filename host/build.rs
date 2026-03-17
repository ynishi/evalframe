use std::{
    env, fs,
    path::{Path, PathBuf},
};

fn main() {
    let lua_dir = find_lua_dir();
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    let mut entries = Vec::new();
    collect_lua_files(&lua_dir, &lua_dir, &mut entries);
    entries.sort_by(|a, b| a.0.cmp(&b.0));

    let mut code = String::from("const EVALFRAME_MODULES: &[(&str, &str)] = &[\n");
    for (rel_path, abs_path) in &entries {
        let content = fs::read_to_string(abs_path)
            .unwrap_or_else(|e| panic!("cannot read {}: {e}", abs_path.display()));
        let fence = raw_fence(&content);
        code.push_str(&format!(
            "    (\"{rel_path}\", r{fence}\"{content}\"{fence}),\n"
        ));
        println!("cargo:rerun-if-changed={}", abs_path.display());
    }
    code.push_str("];\n");

    fs::write(out_dir.join("lua_modules.rs"), &code).unwrap();
}

/// Find the shortest `###...` fence that doesn't appear in `s` followed by `"`.
fn raw_fence(s: &str) -> String {
    let mut n = 0;
    loop {
        let fence = "#".repeat(n);
        let closing = format!("\"{fence}");
        if !s.contains(&closing) {
            return fence;
        }
        n += 1;
    }
}

/// Locate the evalframe Lua source directory.
///
/// Search order:
///   1. EVALFRAME_LUA_DIR env var
///   2. ../evalframe/ (development: sibling of host/)
///   3. lua/evalframe/ (packaged crate fallback)
fn find_lua_dir() -> PathBuf {
    if let Ok(dir) = env::var("EVALFRAME_LUA_DIR") {
        let p = PathBuf::from(dir);
        if p.is_dir() {
            return p;
        }
    }
    let dev = PathBuf::from("../evalframe");
    if dev.is_dir() && dev.join("init.lua").exists() {
        return dev;
    }
    let pkg = PathBuf::from("lua/evalframe");
    if pkg.is_dir() && pkg.join("init.lua").exists() {
        return pkg;
    }
    panic!(
        "Cannot find evalframe Lua sources. \
         Set EVALFRAME_LUA_DIR or ensure ../evalframe/ exists."
    );
}

fn collect_lua_files(base: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>) {
    let mut entries: Vec<_> = fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("cannot read dir {}: {e}", dir.display()))
        .filter_map(|e| e.ok())
        .collect();
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let path = entry.path();
        if path.is_dir() {
            collect_lua_files(base, &path, out);
        } else if path.extension().map_or(false, |e| e == "lua") {
            let rel = path
                .strip_prefix(base)
                .unwrap()
                .to_str()
                .unwrap()
                .replace('\\', "/");
            out.push((rel, path));
        }
    }
}
