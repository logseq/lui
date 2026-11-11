#!/usr/bin/env python3
"""Qualify a completed native Todos package through the public LUI agent."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
MAX_REPLY = 1024 * 1024


class QualificationError(RuntimeError):
    """The completed package could not perform the Todos qualification flow."""


def locate_package(path):
    target = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system())
    if target is None:
        raise QualificationError("This operating system has no native package qualifier")
    library_name = {"macos": "liblui_app.dylib", "linux": "liblui_app.so", "windows": "lui_app.dll"}[target]
    candidates = []
    for receipt_path in path.rglob("lui-delivery.json"):
        if receipt_path.parent.name != "lui":
            continue
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("target") != target or not (receipt_path.parent / library_name).is_file():
            continue
        name = receipt["application"]["name"]
        if target == "macos":
            root = receipt_path.parents[3]
            executable_name = "".join(c for c in name if c.isascii() and c.isalnum()) or "App"
            executable = root / "Contents/MacOS" / executable_name
        else:
            root = receipt_path.parents[1]
            if target == "windows":
                executable_name = ("".join(c for c in name if not ord(c) < 32 and c not in '<>:"/\\|?*').rstrip(". ").lstrip() or "App") + ".exe"
            else:
                executable_name = "".join(c for c in name if c.isascii() and c.isalnum()) or "App"
            executable = root / executable_name
        if executable.is_file():
            candidates.append((root, executable, receipt))
    if len(candidates) != 1:
        raise QualificationError(f"Expected one complete native package in {path}, found {len(candidates)}")
    return candidates[0]


class Agent:
    def __init__(self, connection, deadline, transcript):
        self.connection = connection
        self.reader = connection.makefile("rb")
        self.deadline = deadline
        self.transcript = transcript

    def request(self, **request):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise QualificationError("Packaged application qualification timed out")
        self.connection.settimeout(min(10, remaining))
        self.connection.sendall(json.dumps(request, ensure_ascii=False).encode("utf-8") + b"\n")
        line = self.reader.readline(MAX_REPLY + 2)
        if not line or len(line) > MAX_REPLY + 1 or not line.endswith(b"\n"):
            raise QualificationError("Agent closed its connection or returned an oversized reply")
        reply = json.loads(line)
        self.transcript.write(json.dumps({"request": request, "reply": reply}, ensure_ascii=False) + "\n")
        self.transcript.flush()
        if reply.get("ok") is not True:
            raise QualificationError(f"Agent refused {request}: {reply}")
        return reply

    def close(self):
        try:
            self.reader.close()
        finally:
            self.connection.close()


def nodes(tree):
    pending = list(tree.get("nodes", []))
    while pending:
        node = pending.pop()
        yield node
        pending.extend(node.get("children", []))


def connect(process, address, deadline):
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise QualificationError(f"Packaged application exited during startup: {process.returncode}")
        try:
            return socket.create_connection(address, timeout=min(1, max(0.01, deadline - time.monotonic())))
        except (ConnectionError, TimeoutError):
            time.sleep(min(0.05, max(0, deadline - time.monotonic())))
    raise QualificationError("Packaged application did not open its loopback agent before the deadline")


def stop(process):
    if process.poll() is not None:
        return "exited"
    # Own a process group on POSIX so descendants cannot outlive qualification.
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
    except ProcessLookupError:
        process.wait(timeout=2)
        return "exited"
    try:
        process.wait(timeout=5)
        return "terminated"
    except subprocess.TimeoutExpired:
        try:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
        except ProcessLookupError:
            pass
        process.wait(timeout=2)
        return "killed"


def qualify(package, logs, timeout):
    root, executable, receipt = locate_package(package.resolve())
    logs = logs.resolve()
    if logs == root or logs.is_relative_to(root):
        raise QualificationError("Qualification logs must be outside the signed package")
    logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    removed = ("LUI_OCAML_LIBRARY", "NSH_RUNTIME", "NSH_RUNTIME_DIR", "LD_LIBRARY_PATH",
               "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES")
    for name in removed:
        env.pop(name, None)
    # Release the reservation immediately before launch; failed binding fails qualification.
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        address = reservation.getsockname()
    env["LUI_AGENT_LISTEN"] = f"{address[0]}:{address[1]}"
    title = "Packaged qualification " + uuid.uuid4().hex
    result = {"ok": False, "application": receipt["application"], "executable": str(executable),
              "removedOverrides": list(removed), "todo": title}
    process = None
    agent = None
    try:
        with tempfile.TemporaryDirectory(prefix="lui-packaged-launch-") as outside, \
                (logs / "stdout.log").open("wb") as stdout, \
                (logs / "stderr.log").open("wb") as stderr, \
                (logs / "agent.jsonl").open("w", encoding="utf-8") as transcript:
            if Path(outside).resolve().is_relative_to(ROOT):
                raise QualificationError("Temporary launch directory must be outside the checkout; change TMPDIR")
            result["workingDirectory"] = outside
            deadline = time.monotonic() + timeout
            process = subprocess.Popen([str(executable)], cwd=outside, env=env,
                                       stdout=stdout, stderr=stderr, start_new_session=os.name == "posix")
            try:
                agent = Agent(connect(process, address, deadline), deadline, transcript)
                hello = agent.request(op="hello")
                if hello.get("protocol") != "lui-agent" or hello.get("version") != 1:
                    raise QualificationError(f"Unexpected agent protocol: {hello}")
                result["hello"] = hello
                before = agent.request(op="tree")
                if not any(node.get("props", {}).get("accessibility-label") == "New todo" for node in nodes(before)):
                    raise QualificationError("Package does not contain the real Todos application")
                agent.request(op="type", selector="prop:accessibility-label=New todo", text=title)
                draft = agent.request(op="prop", selector="prop:accessibility-label=New todo", name="text")
                if draft.get("value") != title:
                    raise QualificationError("Todos did not accept the typed draft")
                agent.request(op="press", selector="kind:button&text:Add")
                tree = agent.request(op="tree")
                (logs / "tree.json").write_text(json.dumps(tree, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
                matches = [node for node in nodes(tree) if node.get("props", {}).get("text") == "[ ] " + title]
                if len(matches) != 1:
                    raise QualificationError("Adding the Todos draft did not produce exactly one visible row")
                draft = agent.request(op="prop", selector="prop:accessibility-label=New todo", name="text")
                if draft.get("value") != "":
                    raise QualificationError("Adding the Todos draft did not clear the editor")
                if process.poll() is not None:
                    raise QualificationError(f"Packaged application exited during the flow: {process.returncode}")
                result["ok"] = True
            finally:
                try:
                    if agent:
                        agent.close()
                finally:
                    if process:
                        result["shutdown"] = stop(process)
                        result["exitCode"] = process.returncode
    except Exception as error:
        result["ok"] = False
        result["error"] = str(error)
        raise
    finally:
        (logs / "result.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="Completed application directory or output containing exactly one package")
    parser.add_argument("--logs", type=Path, default=ROOT / "_build/nsh-packaged-qualification")
    parser.add_argument("--timeout", type=float, default=45, help="Startup and agent-flow deadline in seconds")
    args = parser.parse_args()
    if not 0 < args.timeout <= 300:
        parser.error("--timeout must be between 0 and 300 seconds")
    try:
        result = qualify(args.package, args.logs, args.timeout)
    except (OSError, ValueError, QualificationError, subprocess.TimeoutExpired) as error:
        print(f"Packaged qualification failed: {error}; logs: {args.logs.resolve()}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
