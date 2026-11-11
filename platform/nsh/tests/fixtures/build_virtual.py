#!/usr/bin/env python3
"""Build real OCaml qualification fixtures without modifying Dune files."""
import argparse
from pathlib import Path
import platform
import shutil
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]


def execute(command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, **kwargs)


def build_fixture(fixture, *, version=None):
    if fixture == "upgrade" and version not in ("1.0.0", "2.0.0"):
        raise SystemExit("The upgrade fixture needs --version 1.0.0 or 2.0.0")
    if fixture != "upgrade" and version is not None:
        raise SystemExit("Only the upgrade fixture accepts --version")
    source_input = Path(__file__).with_name(f"{fixture}_app.ml")
    suffix = f"-{version}" if version else ""
    output = ROOT / f"_build/nsh/{fixture}{suffix}-qualification"
    target = platform.system()
    if target not in ("Darwin", "Linux", "Windows"):
        raise SystemExit("Qualification fixtures require native macOS, Linux or Windows")
    config = None
    if target == "Windows":
        # Import only on Windows so Unix receipts keep their existing inputs.
        sys.path.insert(0, str(ROOT / "tooling"))
        import build_nsh_windows as windows
        # Reject Cygwin/cross targets before invoking Dune or copying a fixture.
        config = windows.native_config()
    execute(["opam", "exec", "--", "dune", "build", "src/lui.cmxa", "examples/todos/view.pp.ml"], cwd=ROOT, stdout=sys.stderr)
    drivers = sorted((ROOT / "_build/default/.ppx").glob("*/ppx.exe"))
    driver = None
    for candidate in drivers:
        result = subprocess.run([str(candidate), "-print-transformations"], cwd=ROOT,
                                capture_output=True, text=True, check=False)
        if result.returncode == 0 and any("lui" in line.lower() for line in result.stdout.splitlines()):
            driver = candidate
            break
    if driver is None:
        raise SystemExit("No built lui_ppx driver found after building the existing Todos PPX target")
    output.mkdir(parents=True, exist_ok=True)
    source = output / source_input.name
    if version:
        source.write_text(source_input.read_text(encoding="utf-8").replace("__LUI_UPGRADE_VERSION__", version), encoding="utf-8")
    else:
        shutil.copy2(source_input, source)
    include = ROOT / "_build/default/src"
    quote = subprocess.list2cmdline if target == "Windows" else shlex.join
    compiler_arguments = ["-I", include / ".lui.objs/byte", "-I", include,
                          "-ppx", quote([str(driver), "--as-ppx"])]
    if target == "Windows":
        library = windows.link_native_dll(output / f"lui_{fixture}.dll",
                                         [include / "lui.cmxa", source], config=config,
                                         compiler_arguments=compiler_arguments)
    else:
        command = ["opam", "exec", "--", "ocamlfind", "ocamlopt", "-linkpkg", "-linkall",
                   "-package", "ocaml-signal", *compiler_arguments]
        if target == "Linux":
            command += ["-runtime-variant", "_pic", "-ccopt", "-fPIC"]
        object_file = output / f"{fixture}_complete.o"
        command += [include / "lui.cmxa", source, "-output-complete-obj", "-o", object_file]
        execute(command, cwd=output, stdout=sys.stderr)
        ocaml_include = subprocess.check_output(["opam", "exec", "--", "ocamlc", "-where"], cwd=ROOT, text=True).strip()
        library = output / (f"liblui_{fixture}.dylib" if target == "Darwin" else f"liblui_{fixture}.so")
        command = ["cc", "-fPIC", "-shared", "-o", library,
                   ROOT / "platform/bridge/lui_ocaml_bridge.c", object_file,
                   f"-I{ocaml_include}", "-lpthread"]
        if target == "Linux":
            command += ["-ldl", "-lm"]
        execute(command, cwd=output, stdout=sys.stderr)
    if fixture in ("image", "tabs", "navigation", "picker", "fit"):
        execute(["node", ROOT / "tooling/lui_build_receipt.mjs", "write",
                 "--root", ROOT, "--artifact", library,
                 "--command", f"{'python' if target == 'Windows' else 'python3'} platform/nsh/tests/fixtures/build_virtual.py --fixture {fixture}",
                 "--input", "src", "--input", "ppx", "--input", "platform/bridge",
                 "--input", source_input.relative_to(ROOT),
                 "--input", Path(__file__).resolve().relative_to(ROOT),
                 *(["--input", "tooling/build_nsh_windows.py"] if target == "Windows" else [])],
                cwd=ROOT, stdout=sys.stderr)
    return library


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", choices=("virtual", "clock", "upgrade", "image", "tabs", "navigation", "picker", "fit"), default="virtual")
    parser.add_argument("--version", choices=("1.0.0", "2.0.0"))
    args = parser.parse_args()
    library = build_fixture(args.fixture, version=args.version)
    print(library)


if __name__ == "__main__":
    main()
