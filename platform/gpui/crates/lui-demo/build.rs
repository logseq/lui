//! Links the OCaml gallery dylib (`liblui_components.dylib`) into the demo
//! binary. The dylib's install name is `./liblui_components.dylib`, so we
//! copy it into OUT_DIR, rewrite the install name to `@executable_path`, and
//! place a copy next to the produced binary.
//!
//! Override the search dir with `LUI_DYLIB_DIR`; the default is the dune
//! output tree for `examples/components/native`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let repo = manifest
        .ancestors()
        .nth(4)
        .expect("demo crate must live at platform/gpui/crates/lui-demo");

    let dylib_name =
        env::var("LUI_DYLIB_NAME").unwrap_or_else(|_| "liblui_components.dylib".into());
    let dylib_dir = env::var("LUI_DYLIB_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| repo.join("_build/default/examples/components/native"));
    let source = dylib_dir.join(&dylib_name);
    println!("cargo:rerun-if-env-changed=LUI_DYLIB_DIR");
    println!("cargo:rerun-if-env-changed=LUI_DYLIB_NAME");
    println!("cargo:rerun-if-changed={}", source.display());
    if !source.exists() {
        panic!(
            "OCaml dylib not found at {} — build it first:\n  \
             OPAMSWITCH=5.5.0 opam exec -- dune build",
            source.display()
        );
    }

    // dune emits read-only artifacts; a stale copy blocks overwriting.
    let force_copy = |src: &Path, dst: &Path| {
        if dst.exists() {
            fs::remove_file(dst).expect("remove stale dylib copy");
        }
        fs::copy(src, dst).expect("copy dylib");
    };

    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let link_copy = out_dir.join(&dylib_name);
    force_copy(&source, &link_copy);

    // Retarget the install name so the dynamic loader finds the copy placed
    // next to the executable instead of requiring cwd-relative lookup.
    if cfg!(target_os = "macos") {
        let status = Command::new("install_name_tool")
            .arg("-id")
            .arg(format!("@executable_path/{dylib_name}"))
            .arg(&link_copy)
            .status()
            .expect("install_name_tool failed to launch");
        assert!(
            status.success(),
            "install_name_tool failed on {link_copy:?}"
        );

        // OUT_DIR is target/<profile>/build/<pkg>-<hash>/out — the profile
        // dir is three levels up.
        if let Some(profile_dir) = out_dir.ancestors().nth(3) {
            let exe_copy = profile_dir.join(&dylib_name);
            force_copy(&link_copy, &exe_copy);
        }
    }

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!(
        "cargo:rustc-link-lib=dylib={}",
        dylib_name
            .trim_start_matches("lib")
            .trim_end_matches(".dylib")
    );
    println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path");
    let _ = Path::new(&source);
}
