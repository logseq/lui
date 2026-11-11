#!/usr/bin/env python3
"""Build a real native Windows OCaml application DLL for the NSH bridge."""
from __future__ import annotations

import argparse
import ctypes
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
APPLICATIONS = {
    "todos": ("examples/todos/todos_app.cmxa", "examples/todos/native/todos_bridge.cmxa", "examples/todos"),
    "components": ("examples/gallery/gallery_app.cmxa", "examples/components/native/components_bridge.cmxa", "examples/gallery"),
}


def execute(command, *, capture=False, cwd=ROOT):
    result = subprocess.run([str(part) for part in command], cwd=cwd, check=True,
                            text=True, stdout=subprocess.PIPE if capture else sys.stderr)
    return result.stdout.strip() if capture else None


def native_config():
    if platform.system() != "Windows":
        raise ValueError("This builder requires native Windows; it does not cross-compile or use WSL")
    text = execute(["opam", "exec", "--", "ocamlopt", "-config"], capture=True)
    config = dict(line.split(":", 1) for line in text.splitlines() if ":" in line)
    config = {key: value.strip() for key, value in config.items()}
    if config.get("os_type") != "Win32" or config.get("ext_dll") != ".dll":
        raise ValueError("The active OCaml compiler must target native Win32, rather than Cygwin or Unix")
    if config.get("version") != "5.5.1":
        raise ValueError("The Windows qualification requires the pinned OCaml 5.5.1 compiler")
    if config.get("architecture") != "amd64" or config.get("ext_obj") not in (".o", ".obj"):
        raise ValueError("This qualification currently requires native Windows x86_64 OCaml")
    return config


def verify_exports(library):
    # Loading checks the real PE dependency chain and can execute Windows
    # loader/CRT initializers. This probe calls no lui_ocaml_* export; runtime
    # startup on the persistent worker is qualified separately by native CI.
    loaded = ctypes.CDLL(str(library.resolve()))
    import re
    runtime = (ROOT / "platform/nsh/src/runtime.rs").read_text(encoding="utf-8")
    required = set(re.findall(r'required!\("(lui_ocaml_[a-z0-9_]+)"\)', runtime))
    driver = (ROOT / "platform/nsh/src/runtime/driver.rs").read_text(encoding="utf-8")
    generic = driver.split("BridgeConfig::Generic => Self::Generic {", 1)[1].split("},", 1)[0]
    required.update(re.findall(r'symbol!\("(lui_ocaml_[a-z0-9_]+)"\)', generic))
    required.update(("lui_ocaml_virtual_rows_version", "lui_ocaml_virtual_window",
                     "lui_ocaml_scroll_completed", "lui_ocaml_agent_utf8"))
    if not required:
        raise ValueError("No runtime ABI exports were found")
    missing = sorted(name for name in required if not hasattr(loaded, name))
    if missing:
        raise ValueError("Missing native C ABI exports: " + ", ".join(missing))
    return sorted(required)


def link_native_dll(library, inputs, *, config=None, compiler_arguments=()):
    """Link trusted OCaml inputs through the compiler's native DLL toolchain."""
    config = native_config() if config is None else config
    library = Path(library).resolve()
    if library.suffix.lower() != ".dll":
        raise ValueError("The native Windows linker requires a .dll output")
    output = library.parent
    output.mkdir(parents=True, exist_ok=True)
    c_object = output / ("lui_ocaml_bridge" + config["ext_obj"])
    execute(["opam", "exec", "--", "ocamlopt", "-I", ROOT / "platform/bridge",
             "-c", "-o", c_object, ROOT / "platform/bridge/lui_ocaml_bridge.c"], cwd=output)
    # The .dll suffix selects OCaml's configured MainDll/FlexDLL linker. This
    # includes the native runtime and autolink libraries, with matching C ABI.
    execute(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-verbose", "-linkpkg", "-linkall",
             "-package", "ocaml-signal", *compiler_arguments, *inputs,
             c_object, "-output-complete-obj", "-o", library], cwd=output)
    exports = verify_exports(library)
    (output / "ocaml-toolchain.json").write_text(json.dumps({
        "compiler": config, "exports": exports,
        "qualification": "native DLL load and exports only; runtime and package tests run separately",
    }, indent=2) + "\n", encoding="utf-8")
    return library


def build(application, output=None):
    config = native_config()
    app, bridge, sources = APPLICATIONS[application]
    archives = ["src/lui.cmxa", app, bridge]
    execute(["opam", "exec", "--", "dune", "build", *archives])
    output = (output or ROOT / "_build/nsh/windows" / application).resolve()
    library = link_native_dll(output / f"lui_{application}.dll",
                              [ROOT / "_build/default" / name for name in archives],
                              config=config)
    node = shutil.which("node")
    if node:
        command = [node, ROOT / "tooling/lui_build_receipt.mjs", "write", "--root", ROOT,
                   "--artifact", library, "--command", f"python tooling/build_nsh_windows.py --application {application}"]
        for path in ("src", "ppx", sources, str(Path(bridge).parent), "platform/bridge", "tooling/build_nsh_windows.py"):
            command.extend(("--input", path))
        execute(command)
    else:
        print("warning: Node is unavailable; the generic LUI build receipt was not written", file=sys.stderr)
    return library


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--application", choices=APPLICATIONS, default="todos")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        print(build(args.application, args.output))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Windows OCaml DLL build failed: {error}\n")


if __name__ == "__main__":
    main()
