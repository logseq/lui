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


def build_fixture(fixture):
    source_input = Path(__file__).with_name(f"{fixture}_app.ml")
    output = ROOT / f"_build/nsh/{fixture}-qualification"
    target = platform.system()
    if target not in ("Darwin", "Linux"):
        raise SystemExit("The Windows OCaml qualification fixture needs its native toolchain; it is not verified here")
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
    shutil.copy2(source_input, source)
    include = ROOT / "_build/default/src"
    command = ["opam", "exec", "--", "ocamlfind", "ocamlopt", "-linkpkg", "-linkall",
               "-package", "ocaml-signal", "-I", include / ".lui.objs/byte", "-I", include,
               "-ppx", shlex.join([str(driver), "--as-ppx"])]
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
    return library


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", choices=("virtual", "clock"), default="virtual")
    library = build_fixture(parser.parse_args().fixture)
    print(library)


if __name__ == "__main__":
    main()
