#!/usr/bin/env python3
"""Cross-compile the maintained OCaml Gallery with the selected target compiler."""

import argparse
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(arguments, *, cwd=ROOT, capture=False):
    result = subprocess.run(
        [str(argument) for argument in arguments], cwd=cwd, check=True,
        text=True, stdout=subprocess.PIPE if capture else sys.stderr,
    )
    return result.stdout.strip() if capture else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-prefix", type=pathlib.Path, required=True)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    options = parser.parse_args()
    compiler = options.target_prefix.resolve() / "bin/ocamlopt.opt"
    if not compiler.is_file():
        parser.error(f"missing target compiler: {compiler}")
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    run(["opam", "exec", "--", "dune", "build", "ppx/lui_ppx.cmxa"])
    signal = pathlib.Path(run(["opam", "var", "ocaml-signal:lib"], capture=True))
    with tempfile.TemporaryDirectory(prefix="lui-mobile-ocaml-") as directory:
        work = pathlib.Path(directory)
        driver_source = work / "driver.ml"
        driver_source.write_text("let () = Ppxlib.Driver.standalone ()\n")
        driver = work / "driver"
        run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-package", "ppxlib",
             "-linkpkg", "-linkall", ROOT / "_build/default/ppx/lui_ppx.cmxa",
             driver_source, "-o", driver])
        driver_source.unlink()
        sources = [signal / "signal.mli", signal / "signal.ml"]
        sources += [source for source in (ROOT / "src").iterdir()
                    if source.suffix in (".ml", ".mli")
                    and source.stem != "lui_json_view_parse"]
        sources += [source for source in (ROOT / "examples/gallery").iterdir()
                    if source.suffix in (".ml", ".mli") and source.stem != "main"]
        sources.append(ROOT / "examples/components/native/components_bridge.ml")
        for source in sources:
            shutil.copy2(source, work / source.name)
        names = sorted(source.name for source in sources)
        ppx = shlex.join([str(driver), "--as-ppx"])
        dependency = ["opam", "exec", "--", "ocamldep", "-ppx", ppx, "-sort"]
        order = run(dependency + names, cwd=work, capture=True).split()
        for source in order:
            run([compiler, "-I", work, "-ppx", ppx, "-c", source], cwd=work)
        implementations = [name for name in names if name.endswith(".ml")]
        link_order = run(dependency + implementations, cwd=work, capture=True).split()
        objects = [pathlib.Path(name).with_suffix(".cmx") for name in link_order]
        artifact = output / "mobile_app_complete.o"
        run([compiler, "-I", work, "-linkall", "-runtime-variant", "_pic",
             "-I", "+unix", "unix.cmxa", "-I", "+threads", "threads.cmxa", *objects,
             "-output-complete-obj", "-o", artifact], cwd=work)
    print(artifact)


if __name__ == "__main__":
    main()
