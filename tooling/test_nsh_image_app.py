#!/usr/bin/env python3
"""Qualify real native Image decoding and the canonical OCaml Load callback."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time
import zlib

from test_nsh_packaged_app import Agent, QualificationError, ROOT, connect, locate_package, nodes, stop


def png(width, height, color):
    """Make deterministic RGBA pixels without a decoder or third-party package."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = (b"\0" + bytes(color) * width) * height
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def selector(identifier):
    return "prop:accessibility-identifier=" + identifier


def property_value(agent, identifier, name="text"):
    return agent.request(op="prop", selector=selector(identifier), name=name).get("value")


def wait_loads(agent, count):
    expected = f"Image loads {count}"
    while time.monotonic() < agent.deadline:
        value = property_value(agent, "image-loads")
        if value == expected:
            return
        if isinstance(value, str) and value.startswith("Image loads "):
            if int(value.removeprefix("Image loads ")) > count:
                raise QualificationError(f"Duplicate or stale native Load: expected {expected}, got {value}")
        time.sleep(min(0.025, max(0, agent.deadline - time.monotonic())))
    raise QualificationError(f"Native decode did not produce canonical {expected}")


def qualify(package, logs, timeout):
    root, executable, receipt = locate_package(package.resolve())
    logs = logs.resolve()
    if logs == root or logs.is_relative_to(root):
        raise QualificationError("Qualification logs must be outside the signed package")
    logs.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    removed = ("LUI_OCAML_LIBRARY", "NSH_RUNTIME", "NSH_RUNTIME_DIR", "LD_LIBRARY_PATH",
               "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES")
    for name in removed:
        environment.pop(name, None)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        address = reservation.getsockname()
    environment["LUI_AGENT_LISTEN"] = f"{address[0]}:{address[1]}"
    result = {"ok": False, "application": receipt["application"], "executable": str(executable),
              "receipt": receipt, "removedOverrides": list(removed),
              "scope": "Native file-URL decoding, OCaml Load, source replacement and retained editor; not a pixel or HTTP test"}
    process = None
    agent = None
    try:
        with tempfile.TemporaryDirectory(prefix="lui-image-launch-") as outside, \
                (logs / "stdout.log").open("wb") as stdout, \
                (logs / "stderr.log").open("wb") as stderr, \
                (logs / "agent.jsonl").open("w", encoding="utf-8") as transcript:
            outside = Path(outside).resolve()
            if outside.is_relative_to(ROOT):
                raise QualificationError("Image qualification must launch outside the checkout")
            result["workingDirectory"] = str(outside)
            sources = []
            for name, dimensions, color in (("a", (40, 20), (255, 0, 0, 255)),
                                             ("b", (20, 40), (0, 0, 255, 255))):
                data = png(*dimensions, color)
                path = outside / f"{name}.png"
                path.write_bytes(data)
                environment[f"LUI_NSH_IMAGE_URL_{name.upper()}"] = path.as_uri()
                sources.append({"url": path.as_uri(), "width": dimensions[0], "height": dimensions[1],
                                "sha256": hashlib.sha256(data).hexdigest()})
            environment["LUI_NSH_IMAGE_URL_MISSING"] = (outside / "missing.png").as_uri()
            result["sources"] = sources
            deadline = time.monotonic() + timeout
            process = subprocess.Popen([str(executable)], cwd=outside, env=environment,
                                       stdout=stdout, stderr=stderr, start_new_session=os.name == "posix")
            agent = Agent(connect(process, address, deadline), deadline, transcript)
            hello = agent.request(op="hello")
            if hello.get("host") != "Image URL qualification":
                raise QualificationError(f"Package does not contain the Image fixture: {hello}")
            wait_loads(agent, 1)
            before = agent.request(op="tree")
            (logs / "before.json").write_text(json.dumps(before, indent=2) + "\n", encoding="utf-8")
            editor = next(node["id"] for node in nodes(before)
                          if node.get("props", {}).get("accessibility-identifier") == "image-editor")
            agent.request(op="type", selector=selector("image-editor"), text="Retained native Image draft")
            agent.request(op="press", selector=selector("image-second"))
            wait_loads(agent, 2)
            if property_value(agent, "image-probe", "url") != sources[1]["url"]:
                raise QualificationError("Second canonical URL was not accepted")
            agent.request(op="press", selector=selector("image-missing"))
            if property_value(agent, "image-probe", "url") != environment["LUI_NSH_IMAGE_URL_MISSING"]:
                raise QualificationError("Missing URL was not accepted")
            agent.request(op="press", selector=selector("image-first"))
            wait_loads(agent, 3)
            if property_value(agent, "image-editor") != "Retained native Image draft":
                raise QualificationError("Source replacement changed the retained editor draft")
            after = agent.request(op="tree")
            (logs / "after.json").write_text(json.dumps(after, indent=2) + "\n", encoding="utf-8")
            current = next(node["id"] for node in nodes(after)
                           if node.get("props", {}).get("accessibility-identifier") == "image-editor")
            if current != editor:
                raise QualificationError("Source replacement recreated the canonical editor")
            if process.poll() is not None:
                raise QualificationError("Native process exited before qualification completed")
            result.update(ok=True, nativeLoads=3, canonicalEditorId=editor)
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        try:
            if agent:
                agent.close()
        finally:
            if process:
                result["shutdown"] = stop(process)
                result["exitCode"] = process.returncode
            (logs / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--logs", type=Path, default=ROOT / "_build/nsh-image-qualification")
    parser.add_argument("--timeout", type=float, default=45)
    args = parser.parse_args()
    if not 0 < args.timeout <= 300:
        parser.error("--timeout must be between 0 and 300 seconds")
    try:
        result = qualify(args.package, args.logs, args.timeout)
    except (OSError, ValueError, StopIteration, QualificationError, subprocess.TimeoutExpired) as error:
        print(f"Image qualification failed: {error}; logs: {args.logs.resolve()}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
