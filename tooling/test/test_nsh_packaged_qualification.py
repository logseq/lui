"""Exercise package discovery, public agent flow and bounded failure cleanup."""
import importlib.util
import json
import os
from pathlib import Path
import platform
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("nsh_packaged_app", Path(__file__).resolve().parents[1] / "test_nsh_packaged_app.py")
qualifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(qualifier)

APP = '''import json, os, socket, sys
assert "LUI_OCAML_LIBRARY" not in os.environ
assert "NSH_RUNTIME" not in os.environ
assert "NSH_RUNTIME_DIR" not in os.environ
assert "LD_LIBRARY_PATH" not in os.environ
print("fake protocol fixture cwd=" + os.getcwd(), file=sys.stderr, flush=True)
host, port = os.environ["LUI_AGENT_LISTEN"].split(":")
server = socket.socket()
server.bind((host, int(port)))
server.listen(1)
connection, _ = server.accept()
reader = connection.makefile("rb")
draft = ""
title = None
for line in reader:
    request = json.loads(line)
    op = request["op"]
    reply = {"ok": True, "op": op}
    if op == "hello":
        reply.update(protocol="lui-agent", version=1, host="Todos")
    elif op == "type":
        assert request["selector"] == "prop:accessibility-label=New todo"
        draft = request["text"]
    elif op == "prop":
        reply["value"] = draft
    elif op == "press":
        assert request["selector"] == "kind:button&text:Add"
        title, draft = draft, ""
    elif op == "tree":
        children = [{"kind":"text-field", "props":{"accessibility-label":"New todo", "text":draft}, "children":[]}]
        if title:
            children.append({"kind":"text", "props":{"text":"[ ] " + title}, "children":[]})
        reply["nodes"] = [{"kind":"column", "props":{}, "children":children}]
    connection.sendall(json.dumps(reply).encode() + b"\\n")
reader.close()
connection.close()
server.close()
'''


class PackagedAppTests(unittest.TestCase):
    def package(self, directory):
        target = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}[platform.system()]
        root = directory / ("Example.app" if target == "macos" else "Example")
        resources = root / ("Contents/Resources/lui" if target == "macos" else "lui")
        resources.mkdir(parents=True)
        library = {"macos": "liblui_app.dylib", "linux": "liblui_app.so", "windows": "lui_app.dll"}[target]
        (resources / library).write_bytes(b"protocol fixture, not a native qualification")
        (resources / "lui-delivery.json").write_text(json.dumps({"target": target, "application": {"name": "Example", "version": "1.0.0"}}))
        executable = root / ("Contents/MacOS/Example" if target == "macos" else "Example.exe" if target == "windows" else "Example")
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_text(APP)
        return root, executable

    def test_completed_package_flow_cleans_overrides_and_writes_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            root, executable = self.package(directory)
            original_popen = subprocess.Popen
            processes = []

            def launch(command, **kwargs):
                self.assertEqual(command, [str(executable.resolve())])
                self.assertFalse(Path(kwargs["cwd"]).is_relative_to(qualifier.ROOT))
                process = original_popen([sys.executable, *command], **kwargs)
                processes.append(process)
                return process

            with patch.object(qualifier.subprocess, "Popen", side_effect=launch), patch.dict(os.environ, {"LUI_OCAML_LIBRARY": "bad", "NSH_RUNTIME": "bad", "NSH_RUNTIME_DIR": "bad", "LD_LIBRARY_PATH": "bad"}):
                result = qualifier.qualify(root, directory / "logs", 5)
            self.assertTrue(result["ok"])
            self.assertIsNotNone(processes[0].poll())
            tree = json.loads((directory / "logs/tree.json").read_text())
            self.assertEqual(sum(node["props"].get("text") == "[ ] " + result["todo"] for node in qualifier.nodes(tree)), 1)
            self.assertTrue((directory / "logs/agent.jsonl").read_text())
            self.assertIn("fake protocol fixture cwd=", (directory / "logs/stderr.log").read_text())

    def test_failed_startup_is_bounded_and_collects_logs(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            root, executable = self.package(directory)
            executable.write_text('import sys; print("startup failed", file=sys.stderr); sys.exit(7)')
            original_popen = subprocess.Popen
            with patch.object(qualifier.subprocess, "Popen", side_effect=lambda command, **kwargs: original_popen([sys.executable, *command], **kwargs)):
                started = time.monotonic()
                with self.assertRaisesRegex(qualifier.QualificationError, "exited during startup: 7"):
                    qualifier.qualify(root, directory / "logs", 2)
                self.assertLess(time.monotonic() - started, 3)
            result = json.loads((directory / "logs/result.json").read_text())
            self.assertFalse(result["ok"])
            self.assertEqual(result["exitCode"], 7)
            self.assertIn("startup failed", (directory / "logs/stderr.log").read_text())

    def test_ambiguous_or_incomplete_packages_and_in_package_logs_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            first, _ = self.package(directory / "first")
            self.package(directory / "second")
            with self.assertRaisesRegex(qualifier.QualificationError, "found 2"):
                qualifier.locate_package(directory)
            with self.assertRaisesRegex(qualifier.QualificationError, "outside the signed package"):
                qualifier.qualify(first, first / "logs", 1)
            with self.assertRaisesRegex(qualifier.QualificationError, "found 0"):
                qualifier.locate_package(directory / "missing")

    def test_unresponsive_startup_is_terminated_at_the_deadline(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            root, executable = self.package(directory)
            executable.write_text("import time; time.sleep(30)")
            original_popen = subprocess.Popen
            processes = []

            def launch(command, **kwargs):
                process = original_popen([sys.executable, *command], **kwargs)
                processes.append(process)
                return process

            with patch.object(qualifier.subprocess, "Popen", side_effect=launch):
                started = time.monotonic()
                with self.assertRaisesRegex(qualifier.QualificationError, "before the deadline"):
                    qualifier.qualify(root, directory / "logs", 0.1)
                self.assertLess(time.monotonic() - started, 2)
            self.assertIsNotNone(processes[0].poll())
            result = json.loads((directory / "logs/result.json").read_text())
            self.assertFalse(result["ok"])
            self.assertIn(result["shutdown"], ("terminated", "killed"))

    def test_agent_rejects_oversized_reply_without_buffering_it(self):
        import io
        connection, peer = socket.socketpair()
        with connection, peer:
            agent = qualifier.Agent(connection, time.monotonic() + 1, io.StringIO())
            agent.reader.close()
            agent.reader = io.BytesIO(b"x" * (qualifier.MAX_REPLY + 2))
            with patch.object(qualifier.socket.socket, "sendall"), self.assertRaisesRegex(qualifier.QualificationError, "oversized"):
                agent.request(op="tree")
            agent.close()


if __name__ == "__main__":
    unittest.main()
