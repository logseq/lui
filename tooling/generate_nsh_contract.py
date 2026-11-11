#!/usr/bin/env python3
"""Export the canonical LUI native contract for the NSH adapter."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from nsh_contract_codegen import compile_validators, scalar_types

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ["schema/components.json", "src/lui_protocol.ml", "src/lui_protocol.mli",
          "src/lui_wire_schema.ml", "src/lui_extension.ml", "tooling/export_native_contract.ml",
          "tooling/generate_nsh_contract.py", "tooling/nsh_contract_codegen.py"]
OUTPUT = ROOT / "platform/nsh/contract.json"
VALIDATORS = ROOT / "platform/nsh/src/contract_generated.rs"
ORACLE = ROOT / "platform/nsh/tests/fixtures/contract_oracle.json"


def source_hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for name in INPUTS}


def export_contract():
    subprocess.run(["opam", "exec", "--", "dune", "build", "src/lui.cmxa"], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix="lui-nsh-contract-") as directory:
        temporary = Path(directory)
        source = temporary / "export_native_contract.ml"
        shutil.copy2(ROOT / "tooling/export_native_contract.ml", source)
        binary = temporary / "export"
        subprocess.run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-linkpkg",
                        "-package", "compiler-libs.common,yojson,ocaml-signal", "-I",
                        str(ROOT / "_build/default/src/.lui.objs/byte"), "-I",
                        str(ROOT / "_build/default/src"), str(ROOT / "_build/default/src/lui.cmxa"),
                        str(source), "-o", str(binary)], cwd=ROOT, check=True)
        return json.loads(subprocess.check_output([str(binary), str(ROOT / "src/lui_protocol.ml")], cwd=ROOT))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    contract = export_contract()
    metadata = {key: value for key, value in contract.items() if key not in ("validators", "oracle")}
    metadata["kinds"] = {kind: {key: value for key, value in definition.items() if key != "presence"}
                         for kind, definition in contract["kinds"].items()}
    metadata["sourceHashes"] = source_hashes()
    schema = json.loads((ROOT / "schema/components.json").read_text(encoding="utf-8"))
    metadata["scalarTypes"] = scalar_types(schema, contract)
    validators = compile_validators(schema, contract)
    rustup = shutil.which("rustup") or str(Path.home() / ".cargo/bin/rustup")
    formatted = subprocess.run([rustup, "run", "1.97.0", "rustfmt", "--edition", "2024"],
                               input=validators, text=True, capture_output=True, check=True).stdout
    outputs = {OUTPUT: json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
               VALIDATORS: formatted,
               ORACLE: json.dumps(contract["oracle"], ensure_ascii=False, indent=2) + "\n"}
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, rendered in outputs.items()
                 if not path.exists() or path.read_bytes() != rendered.encode("utf-8")]
        if stale:
            raise SystemExit("NSH contract is stale (" + ", ".join(stale) + "); run python3 tooling/generate_nsh_contract.py")
        return
    for path, rendered in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")


if __name__ == "__main__":
    main()
