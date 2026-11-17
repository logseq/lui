"""Opt-in real-system WebView lifetime regression; run on the target desktop.

LUI_DESKTOP_TEST_APP must be the native executable inside a built app. Linux
requires a display (or Xvfb); no WebView implementation is mocked here.
"""
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import plistlib
import shutil
import threading
import time
import unittest


@unittest.skipUnless(os.environ.get("LUI_DESKTOP_TEST_APP"), "Set LUI_DESKTOP_TEST_APP to run native window checks")
class DesktopWindowLifetime(unittest.TestCase):
    def test_remind_me_later_exits_the_helper_and_releases_its_webkit_processes(self):
        class Page(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = b'''<!doctype html><html><head><meta charset="utf-8"></head><body>
                    <p>Testing update-window cleanup</p>
                    <script>window.addEventListener("load", () => {
                      setTimeout(() => window.__lui_later(), 1200);
                    });</script></body></html>'''
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args):
                pass

        def webkit_processes():
            if sys.platform != "darwin":
                return set()
            listing = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
            return {int(line.strip().split(None, 1)[0]) for line in listing.splitlines()
                    if "/WebKit.framework/" in line}

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Page)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        executable = str(Path(os.environ["LUI_DESKTOP_TEST_APP"]).resolve())
        probe = tempfile.TemporaryDirectory(prefix="lui-scheme-window-")
        if sys.platform == "darwin":
            root = Path(__file__).resolve().parents[2]
            source = root / "platform/desktop"
            app = Path(probe.name) / "Scheme Probe.app/Contents"
            (app / "MacOS").mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "probe", "CFBundleIdentifier": "dev.lui.scheme-lifecycle-probe",
                "CFBundlePackageType": "APPL", "CFBundleName": "LUI Scheme Lifecycle Probe"}))
            include = subprocess.check_output(["opam", "exec", "--", "ocamlc", "-where"], text=True).strip()
            native = Path(probe.name) / "scheme.o"
            subprocess.run(["c++", "-std=c++17", "-O2", "-I", include, "-c", str(source / "macos_scheme.mm"),
                            "-o", str(native)], check=True)
            reply = Path(probe.name) / "reply.o"
            subprocess.run(["c++", "-std=c++17", "-O2", "-I", include, "-c", str(source / "lui_desktop_reply.cc"),
                            "-o", str(reply)], check=True)
            executable = str(app / "MacOS/probe")
            shutil.copy2(source / "test/scheme_probe.ml", Path(probe.name) / "scheme_probe.ml")
            subprocess.run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-O3", "-thread", "-package", "unix,threads", "-linkpkg",
                            "-o", executable, "scheme_probe.ml", str(native), str(reply),
                            "-cclib", "-lc++", "-cclib", "-framework", "-cclib", "WebKit",
                            "-cclib", "-framework", "-cclib", "Cocoa"], cwd=probe.name, check=True)
        try:
            for iteration in range(3):
                baseline = webkit_processes()
                arguments = [executable] if sys.platform == "darwin" else [executable, "--lui-updater", "LUI Update Lifecycle Probe",
                                            f"http://127.0.0.1:{server.server_port}/"]
                process = subprocess.Popen(arguments,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                observed = set()
                deadline = time.monotonic() + 15
                while process.poll() is None and time.monotonic() < deadline:
                    observed |= webkit_processes() - baseline
                    time.sleep(0.05)
                try:
                    output, error = process.communicate(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
                    output, error = process.communicate()
                    self.fail("Remind Me Later did not exit the native updater helper: " + output + error)
                self.assertEqual(process.returncode, 0, output + error)
                if sys.platform == "darwin":
                    self.assertEqual(output.splitlines(), ["scheme-ready", "scheme-later", "scheme-closed"])
                deadline = time.monotonic() + 5
                while observed & webkit_processes() and time.monotonic() < deadline:
                    time.sleep(0.1)
                self.assertFalse(observed & webkit_processes(),
                                 f"Iteration {iteration}: helper WebKit processes survived closure")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            probe.cleanup()


if __name__ == "__main__":
    unittest.main()
