"""Exercise the real Go-only freshness gate against isolated source mutations."""
import json
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ContractGenerationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="lui-contract-check-")
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        contract = json.loads((ROOT / "schema/mygo-manifest.json").read_text())
        files = list(contract["sourceHashes"]) + ["schema/mygo-manifest.json",
            "tooling/generate_mygo_schema.py", "tooling/mygo_contract_codegen.py",
            "tooling/mygo_support.py", "platform/mygo/schema_generated.go",
            "platform/mygo/capabilities.json", "platform/mygo/SUPPORT.md"]
        inventory = json.loads((ROOT / "platform/mygo/capabilities.json").read_text())
        files += [str(path.relative_to(ROOT)) for path in (ROOT / "platform/mygo").glob("*_test.go")]
        files += [info["exception"]["source"] for info in inventory["properties"].values() if "exception" in info]
        for name in files:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)

    def check(self):
        return subprocess.run([sys.executable, str(self.root / "tooling/generate_mygo_schema.py"), "--check"],
                              capture_output=True, text=True)

    def test_current_export_needs_no_ocaml_build(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_full_contract_is_needed_or_created(self):
        legacy = self.root / "schema/mygo-contract.json"
        self.assertFalse(legacy.exists())
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(legacy.exists())
        result = subprocess.run([sys.executable, str(self.root / "tooling/generate_mygo_schema.py")],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(legacy.exists())

    def test_oracle_output_requires_export(self):
        result = subprocess.run([sys.executable, str(self.root / "tooling/generate_mygo_schema.py"),
                                 "--oracle-output", str(self.root.parent / "unused-oracle.json")],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires --export", result.stdout + result.stderr)

    def test_oracle_output_cannot_write_into_repository(self):
        result = subprocess.run([sys.executable, str(self.root / "tooling/generate_mygo_schema.py"),
                                 "--export", "--oracle-output", str(self.root / "schema/oracle.json")],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the repository", result.stdout + result.stderr)
        self.assertFalse((self.root / "schema/oracle.json").exists())

    def test_manifest_contains_only_hashes_counts_and_minimal_baselines(self):
        manifest = json.loads((self.root / "schema/mygo-manifest.json").read_text())
        self.assertEqual(set(manifest), {"version", "sourceHashes", "generatedGoHash", "kinds"})
        self.assertEqual(len(manifest["generatedGoHash"]), 64)
        for kind in manifest["kinds"].values():
            self.assertEqual(set(kind), {"contractHash", "propertyCount", "childCount", "eventCount", "baseline"})
        self.assertLess((self.root / "schema/mygo-manifest.json").stat().st_size, 40000)

    def test_windows_checkout_line_endings_preserve_freshness(self):
        contract = json.loads((self.root / "schema/mygo-manifest.json").read_text())
        for name in contract["sourceHashes"]:
            path = self.root / name
            path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_canonical_source_change_invalidates_export(self):
        contract = json.loads((self.root / "schema/mygo-manifest.json").read_text())
        for name in contract["sourceHashes"]:
            with self.subTest(source=name):
                path = self.root / name
                original = path.read_bytes()
                path.write_bytes(original + b"\n")
                result = self.check()
                path.write_bytes(original)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("contract is stale", result.stdout + result.stderr)

    def test_stale_support_document_is_rejected(self):
        path = self.root / "platform/mygo/SUPPORT.md"
        path.write_text(path.read_text() + "\nUnreviewed documentation\n")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("capabilities document is stale", result.stdout + result.stderr)

    def test_generated_go_hash_change_is_rejected(self):
        path = self.root / "schema/mygo-manifest.json"
        data = json.loads(path.read_text())
        data["generatedGoHash"] = "0" * 64
        path.write_text(json.dumps(data))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("schema is stale", result.stdout + result.stderr)

    def test_generated_predicate_changes_are_rejected(self):
        path = self.root / "platform/mygo/schema_generated.go"
        path.write_text(path.read_text() + "\n// unreviewed change\n")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("schema is stale", result.stdout + result.stderr)

    def test_export_builds_before_linking_even_when_source_mtimes_are_newer(self):
        # Identical generated files may be rewritten after Dune cached the build.
        # Only Dune's content digests can decide whether the library is current.
        library = self.root / "_build/default/src/lui.cmxa"
        library.parent.mkdir(parents=True)
        library.touch()
        os.utime(library, (1, 1))
        for name in json.loads((self.root / "schema/mygo-manifest.json").read_text())["sourceHashes"]:
            os.utime(self.root / name, (2, 2))
        spec = importlib.util.spec_from_file_location("mygo_generation_under_test",
            self.root / "tooling/generate_mygo_schema.py")
        module = importlib.util.module_from_spec(spec)
        with mock.patch.object(sys, "path", [str(self.root / "tooling")] + sys.path):
            spec.loader.exec_module(module)
        with mock.patch.object(module.subprocess, "run", return_value=
                subprocess.CompletedProcess([], 0, stdout="{}")) as run:
            module.export_contract()
        self.assertEqual(len(run.call_args_list), 3)
        self.assertEqual(run.call_args_list[0].args[0],
            ["opam", "exec", "--", "dune", "build", "src/lui.cmxa"])
        self.assertEqual(run.call_args_list[0].kwargs, {"cwd": self.root.resolve(), "check": True})
        self.assertIn("ocamlopt", run.call_args_list[1].args[0])


if __name__ == "__main__":
    unittest.main()
