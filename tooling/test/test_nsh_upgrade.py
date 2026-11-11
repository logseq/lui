"""Validate upgrade-driver preparation and protocol orchestration with fixtures."""
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "qualify_nsh_upgrade.py"
sys.path.insert(0, str(MODULE.parent))
try:
    SPEC = importlib.util.spec_from_file_location("qualify_nsh_upgrade", MODULE)
    upgrade = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(upgrade)
finally:
    sys.path.pop(0)

PROTOCOL_FIXTURE = '''import json, os, socket, sys
VERSION = "1.0.0"
assert "LUI_OCAML_LIBRARY" not in os.environ
assert "NSH_RUNTIME" not in os.environ
print("lui-upgrade-rust=" + VERSION, file=sys.stderr, flush=True)
host, port = os.environ["LUI_AGENT_LISTEN"].split(":")
server = socket.socket()
server.bind((host, int(port)))
server.listen(1)
connection, _ = server.accept()
draft, count = "", 0
with connection.makefile("rb") as reader:
    for line in reader:
        request = json.loads(line)
        op = request["op"]
        answer = {"ok": True, "op": op}
        if op == "hello":
            answer.update(protocol="lui-agent", version=1, host="Upgrade fixture " + VERSION)
        elif op == "tree":
            answer["nodes"] = [{"kind":"column", "props":{}, "children":[
                {"kind":"text", "props":{"text":"OCaml upgrade " + VERSION}, "children":[]}
            ]}]
        elif op == "type":
            assert request["selector"] == "prop:accessibility-label=Upgrade editor"
            draft = request["text"]
        elif op == "press":
            assert request["selector"] == "kind:button&text:Increment"
            count += 1
        elif op == "prop":
            assert request["name"] == "text"
            answer["value"] = "Count " + str(count) if "upgrade-count" in request["selector"] else draft
        connection.sendall(json.dumps(answer).encode() + b"\\n")
connection.close()
server.close()
'''


class UpgradeDriverTests(unittest.TestCase):
    def test_fixture_crate_reuses_real_lui_and_one_immutable_nsh_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            application = root / "real-lui"
            application.mkdir()
            (application / "Cargo.lock").write_text("version=4\n")
            source = {"repository": "https://github.com/logseq/nsh", "revision": "a" * 40}
            with patch.object(upgrade, "APP", application):
                upgrade.prepare_app(root / "fixture", "1.0.0", source)
            manifest = tomllib.loads((root / "fixture/Cargo.toml").read_text())
            self.assertEqual(manifest["dependencies"]["lui-nsh"]["path"], str(application))
            self.assertEqual(manifest["dependencies"]["nsh-core"]["rev"], source["revision"])
            self.assertEqual(manifest["package"]["version"], "1.0.0")
            code = (root / "fixture/src/lib.rs").read_text()
            self.assertIn("lui_nsh::app::desktop()", code)
            self.assertIn('env!("CARGO_PKG_VERSION")', code)
            config = json.loads((root / "fixture/nsh.json").read_text())
            self.assertEqual(config["updater"]["publicKey"], upgrade.PUBLIC)
            self.assertEqual(config["updater"]["url"], "https://updates.example.invalid/latest.json")

    def package(self, root, code):
        executable = root / "protocol-fixture.py"
        executable.write_text(code)
        return executable

    def observe(self, root, code):
        executable = self.package(root, code)
        receipt = {"application": {"version": "1.0.0"}}
        original_popen = subprocess.Popen

        def launch(command, **kwargs):
            self.assertFalse(Path(kwargs["cwd"]).is_relative_to(upgrade.ROOT))
            return original_popen([sys.executable, *command], **kwargs)

        with patch.object(upgrade.launch, "locate_package", return_value=(root, executable, receipt)), \
                patch.object(upgrade.subprocess, "Popen", side_effect=launch), \
                patch.dict(os.environ, {"LUI_OCAML_LIBRARY": "bad", "NSH_RUNTIME": "bad"}):
            return upgrade.observe(root, "1.0.0", root / "logs", timeout=3)

    def test_driver_requires_both_markers_and_real_protocol_actions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = self.observe(root, PROTOCOL_FIXTURE)
            self.assertTrue(result["rustMarker"])
            self.assertTrue(result["ocamlMarker"])
            self.assertTrue(result["realReducerEditAndPress"])
            self.assertTrue((root / "logs/tree.json").is_file())

    def test_wrong_compiled_rust_half_is_rejected_after_the_protocol_flow(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wrong = PROTOCOL_FIXTURE.replace('print("lui-upgrade-rust=" + VERSION', 'print("wrong-rust=" + VERSION')
            with self.assertRaisesRegex(upgrade.launch.QualificationError, "Rust version marker"):
                self.observe(root, wrong)

    def test_wrong_compiled_ocaml_half_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            wrong = PROTOCOL_FIXTURE.replace('host="Upgrade fixture " + VERSION', 'host="Upgrade fixture 0.0.0"')
            with self.assertRaisesRegex(upgrade.launch.QualificationError, "Wrong compiled OCaml"):
                self.observe(root, wrong)


if __name__ == "__main__":
    unittest.main()
