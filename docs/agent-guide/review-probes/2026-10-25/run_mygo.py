#!/usr/bin/env python3
"""Probe MyGo 0.6.4 in an isolated module without changing the adapter pin."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="also run existing adapter tests")
    parser.add_argument("--library", type=Path, help="existing OCaml Todos shared library")
    args = parser.parse_args()
    if args.library and not args.all:
        parser.error("--library requires --all")
    library = args.library.resolve() if args.library else None
    if library and not library.is_file():
        parser.error(f"shared library does not exist: {library}")

    here = Path(__file__).resolve().parent
    source = here.parents[3] / "platform/mygo"
    env = os.environ.copy()
    env["GOTOOLCHAIN"] = "go1.27.3"
    env.pop("LUI_MYGO_TEST_LIBRARY", None)
    if library:
        env["LUI_MYGO_TEST_LIBRARY"] = str(library)

    with tempfile.TemporaryDirectory(prefix="lui-mygo-research-") as directory:
        work = Path(directory)
        for path in [*source.glob("*.go"), source / "go.mod", source / "go.sum"]:
            shutil.copy2(path, work / path.name)
        shutil.copytree(source / "cmd", work / "cmd")
        shutil.copy2(here / "mygo_capabilities_test.go", work / "capability_probe_test.go")
        subprocess.run(
            ["go", "mod", "edit", "-go=1.27.3", "-require=github.com/egoist/mygo@v0.6.4"],
            cwd=work, env=env, check=True,
        )
        command = ["go", "test", "-mod=mod", "-race", "-count=1", "-v"]
        if not args.all:
            command += ["-run", "^TestResearch"]
        command += ["./..."]
        result = subprocess.run(command, cwd=work, env=env)
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
