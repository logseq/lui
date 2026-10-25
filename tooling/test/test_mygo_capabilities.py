"""Reject incomplete support claims through the public generation command."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class CapabilitiesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="lui-capabilities-")
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        contract = json.loads((ROOT / "schema/mygo-manifest.json").read_text())
        files = set(contract["sourceHashes"]) | {
            "schema/mygo-manifest.json", "platform/mygo/schema_generated.go",
            "platform/mygo/capabilities.json"}
        files.update(str(p.relative_to(ROOT)) for p in (ROOT / "tooling").glob("*mygo*.py"))
        files.update(str(p.relative_to(ROOT)) for p in (ROOT / "platform/mygo").glob("*_test.go"))
        if (ROOT / "platform/mygo/SUPPORT.md").exists():
            files.add("platform/mygo/SUPPORT.md")
        inventory = json.loads((ROOT / "platform/mygo/capabilities.json").read_text())
        for info in inventory["properties"].values():
            if "exception" in info:
                files.add(info["exception"]["source"])
        for name in files:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)

    def mutate(self, change):
        path = self.root / "platform/mygo/capabilities.json"
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data))
        return subprocess.run([sys.executable,
            str(self.root / "tooling/generate_mygo_schema.py"), "--check"],
            capture_output=True, text=True)

    def assert_rejected(self, change):
        result = self.mutate(change)
        self.assertNotEqual(result.returncode, 0, "generation accepted an incomplete support claim")
        self.assertIn("capabilit", result.stdout + result.stderr)

    def test_missing_kind_is_rejected(self):
        self.assert_rejected(lambda d: d["kinds"].pop("button"))

    def test_unknown_removed_kind_is_rejected(self):
        self.assert_rejected(lambda d: d["kinds"].update({"br": d["kinds"]["text"]}))

    def test_changed_per_kind_contract_hash_is_rejected(self):
        self.assert_rejected(lambda d: d["kinds"]["button"].update(contractHash="0" * 64))

    def test_missing_per_kind_contract_hash_is_rejected(self):
        self.assert_rejected(lambda d: d["kinds"]["button"].pop("contractHash"))

    def test_duplicate_contract_lists_are_rejected(self):
        self.assert_rejected(lambda d: d["kinds"]["button"].update(properties=["tooltip"]))

    def test_unknown_event_behavior_is_rejected(self):
        self.assert_rejected(lambda d: d["events"].update(unknown=d["events"]["press"]))

    def test_duplicate_record_is_rejected(self):
        path = self.root / "platform/mygo/capabilities.json"
        text = path.read_text()
        path.write_text(text.replace('"version": 1', '"version": 1, "version": 1', 1))
        result = subprocess.run([sys.executable,
            str(self.root / "tooling/generate_mygo_schema.py"), "--check"],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, "generation accepted duplicate records")
        self.assertIn("capabilit", result.stdout + result.stderr)

    def test_missing_property_behavior_is_rejected(self):
        self.assert_rejected(lambda d: d["properties"].pop("overscan"))

    def test_missing_evidence_is_rejected(self):
        self.assert_rejected(lambda d: d["properties"]["overscan"].update(evidence=[]))

    def test_nonexistent_test_reference_is_rejected(self):
        self.assert_rejected(lambda d: d["properties"]["overscan"].update(
            evidence=["collections_test.go:TestNotActuallyPresent"]))

    def test_exception_without_reason_is_rejected(self):
        self.assert_rejected(lambda d: d["properties"]["source"]["exception"].pop("reason"))

    def test_missing_event_evidence_is_rejected(self):
        self.assert_rejected(lambda d: d["events"]["picked"].update(evidence=[]))


if __name__ == "__main__":
    unittest.main()
