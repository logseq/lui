"""Run standalone review probes without changing project test declarations."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
TARGETS = sys.argv[1:] or ["runtime", "web"]


def run(args, cwd=ROOT, env=None):
    subprocess.run(["rtk", "proxy", *args], cwd=cwd, env=env, check=True)


with tempfile.TemporaryDirectory(prefix="lui-review-") as scratch:
    scratch = Path(scratch)
    if "runtime" in TARGETS:
        run(["opam", "exec", "--", "dune", "build", "src/lui.cmxa"])
        source = scratch / "runtime_review.ml"
        shutil.copyfile(HERE / source.name, source)
        binary = scratch / "runtime_review"
        run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-package", "ocaml-signal",
             "-linkpkg", "-I", "_build/default/src/.lui.objs/byte",
             "-I", "_build/default/src/.lui.objs/native", "_build/default/src/lui.cmxa",
             str(source), "-o", str(binary)])
        run([str(binary)])
    if "web" in TARGETS:
        run(["opam", "exec", "--", "dune", "build", "@web"])
        run(["node", str(HERE / "web_review.mjs")], env={**os.environ, "LUI_REVIEW_ROOT": str(ROOT)})
