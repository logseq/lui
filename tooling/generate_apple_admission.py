#!/usr/bin/env python3
"""Export Apple's property matrix and conformance oracle from canonical OCaml.

Run --export after admission changes, then generate_component_schema.mjs.
--check only verifies source hashes and needs no compiler or installed SDK.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'schema/apple-property-admission.json'
SOURCES = ['schema/components.json', 'src/lui_protocol.ml',
           'tooling/export_apple_admission.ml']


def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes().replace(b'\r\n', b'\n')).hexdigest()
            for p in SOURCES}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.export:
        subprocess.run(['opam', 'exec', '--', 'dune', 'build', 'src/lui.cmxa'], cwd=ROOT, check=True)
        with tempfile.TemporaryDirectory(prefix='lui-apple-admission-') as folder:
            source = Path(folder) / 'export_apple_admission.ml'
            shutil.copyfile(ROOT / 'tooling/export_apple_admission.ml', source)
            program = Path(folder) / 'export'
            subprocess.run(['opam', 'exec', '--', 'ocamlfind', 'ocamlopt', '-package',
                'compiler-libs.common,yojson,ocaml-signal', '-linkpkg',
                '-I', str(ROOT / '_build/default/src/.lui.objs/byte'),
                '-I', str(ROOT / '_build/default/src/.lui.objs/native'),
                str(ROOT / '_build/default/src/lui.cmxa'), str(source), '-o', str(program)], check=True)
            contract = json.loads(subprocess.check_output([str(program), str(ROOT / 'src/lui_protocol.ml')]))
        contract['sourceHashes'] = hashes()
        OUTPUT.write_text(json.dumps(contract, sort_keys=True, separators=(',', ':')) + '\n')
    contract = json.loads(OUTPUT.read_text())
    if contract['sourceHashes'] != hashes():
        raise SystemExit('Apple admission is stale; run tooling/generate_apple_admission.py --export')


if __name__ == '__main__':
    main()
