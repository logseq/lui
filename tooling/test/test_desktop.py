"""Exercise the real OCaml update engine with packages from the release writer."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("desktop", ROOT / "tooling/desktop.py")
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)


class DesktopUpdates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="lui-desktop-tests-")
        cls.work = Path(cls.workspace.name)
        for name in ["lui_desktop_update.mli", "lui_desktop_update.ml"]:
            shutil.copy2(desktop.SOURCE / name, cls.work)
        shutil.copy2(desktop.SOURCE / "test/update_probe.ml", cls.work)
        desktop.run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-package", desktop.PACKAGES,
                     "-thread", "-linkpkg", "lui_desktop_update.mli", "lui_desktop_update.ml",
                     "update_probe.ml", "-o", "probe"], cwd=cls.work)
        cls.private = cls.work / "private.pem"
        cls.public = cls.work / "public.hex"
        desktop.keygen(type("Args", (), {"private": cls.private, "public": cls.public})())

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=self.work)
        self.directory = Path(self.temporary.name)
        self.old = self.directory / "old"
        self.new = self.directory / "new"
        self.old.mkdir()
        self.new.mkdir()
        self.config = dict(name="Demo", slug="demo", identifier="dev.lui.demo", version="1.0.0", build=1,
                           platform="linux-amd64", updates=dict(url="https://example.com/update-linux-amd64.json",
                                                                public_key=self.public.read_text().strip()))
        for app, build in [(self.old, 1), (self.new, 2)]:
            (app / "lui-desktop.json").write_text(json.dumps(dict(self.config, build=build)))
            (app / "app").write_bytes(b"executable" * 10000)
            (app / "app").chmod(0o755)
            (app / "frontend").mkdir()
            (app / "frontend/index.html").write_text(f"Build {build}")
        (self.old / "removed.txt").write_text("Remove this file")
        (self.new / "added.txt").write_text("Added in version 2")

    def tearDown(self):
        self.temporary.cleanup()

    def probe(self, *args, success=True):
        result = subprocess.run([str(self.work / "probe"), *map(str, args)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return result.stdout.strip()

    def feed(self):
        output = self.directory / "release"
        desktop.release(type("Args", (), dict(app=self.new, output=output, key=self.private,
                        base_url="https://example.com/releases", previous=[self.old], notes=None))())
        return output / "update-linux-amd64.json"

    def test_signed_manifest_rejects_tampering_wrong_app_platform_and_replay(self):
        feed = self.feed()
        arguments = [self.public.read_text().strip(), "dev.lui.demo", "linux-amd64"]
        self.assertEqual(self.probe("authenticate", *arguments, 1, feed), "1.0.0:2:true")
        self.assertEqual(self.probe("authenticate", *arguments, 2, feed), "current")
        self.probe("authenticate", arguments[0], "dev.other.app", arguments[2], 1, feed, success=False)
        self.probe("authenticate", arguments[0], arguments[1], "windows-amd64", 1, feed, success=False)
        envelope = json.loads(feed.read_text())
        envelope["payload"] = envelope["payload"].replace('"build":2', '"build":3')
        feed.write_text(json.dumps(envelope))
        self.probe("authenticate", *arguments, 1, feed, success=False)

    def test_full_and_delta_reconstruct_the_identical_complete_tree(self):
        full = self.directory / "full"
        delta = self.directory / "delta"
        desktop.write_package(self.new, full)
        desktop.write_package(self.new, delta, self.old)
        self.assertLess(delta.stat().st_size, full.stat().st_size / 10)
        for name, package in [("full-tree", full), ("delta-tree", delta)]:
            destination = self.directory / name
            self.probe("stage", package, self.old, destination)
            self.assertEqual([p.relative_to(self.new) for p in desktop.tree_files(self.new)],
                             [p.relative_to(destination) for p in desktop.tree_files(destination)])
            for path in desktop.tree_files(self.new):
                target = destination / path.relative_to(self.new)
                self.assertEqual(target.read_bytes(), path.read_bytes())
                if os.name != "nt":
                    self.assertEqual(target.stat().st_mode & 0o777, path.stat().st_mode & 0o777)

    def test_modified_delta_source_fails_and_cleans_staging(self):
        delta = self.directory / "delta"
        desktop.write_package(self.new, delta, self.old)
        (self.old / "app").write_bytes(b"corrupted!" * 10000)
        destination = self.directory / "stage"
        self.probe("stage", delta, self.old, destination, success=False)
        self.assertFalse(destination.exists())

    def test_corrupted_payload_fails_and_cleans_staging(self):
        package = self.directory / "package"
        desktop.write_package(self.new, package)
        contents = bytearray(package.read_bytes())
        contents[-1] ^= 1
        package.write_bytes(contents)
        self.probe("stage", package, self.old, self.directory / "stage", success=False)
        self.assertFalse((self.directory / "stage").exists())

    def package_with_entries(self, entries, payload=b""):
        package = self.directory / "malformed"
        index = json.dumps(dict(schema=1, files=entries)).encode()
        package.write_bytes(b"LUIUPD1\n" + struct.pack(">I", len(index)) + index + payload)
        return package

    def test_rejects_traversal_case_collisions_invalid_offsets_and_modes(self):
        import hashlib
        entry = dict(path="file", size=1, sha256=hashlib.sha256(b"x").hexdigest(), mode=0o644, offset=0)
        cases = [
            [dict(entry, path="../escaped")], [dict(entry, path="/absolute")],
            [dict(entry, path="C:\\Windows\\file")], [dict(entry, path="folder//file")],
            [dict(entry, offset=-1)], [dict(entry, offset=1)], [dict(entry, size=2)],
            [dict(entry, mode=0o4755)], [entry, dict(entry, path="FILE", offset=1)],
            [entry, dict(entry, path="file/child", offset=1)],
        ]
        for entries in cases:
            with self.subTest(entries=entries):
                package = self.package_with_entries(entries, b"xx")
                destination = self.directory / "stage"
                self.probe("stage", package, self.old, destination, success=False)
                self.assertFalse(destination.exists())
        self.assertFalse((self.directory / "escaped").exists())

    @unittest.skipIf(os.name == "nt", "Requires unprivileged symbolic links")
    def test_delta_cannot_read_through_symlink(self):
        delta = self.directory / "delta"
        desktop.write_package(self.new, delta, self.old)
        external = self.directory / "external"
        shutil.move(self.old / "app", external)
        (self.old / "app").symlink_to(external)
        self.probe("stage", delta, self.old, self.directory / "stage", success=False)

    def test_installer_replaces_tree_and_preserves_user_data_outside_it(self):
        user_data = self.directory / "user-data"
        user_data.write_text("preserved")
        self.probe("install", self.new, self.old)
        self.assertEqual((self.old / "added.txt").read_text(), "Added in version 2")
        self.assertFalse((self.old / "removed.txt").exists())
        self.assertEqual(user_data.read_text(), "preserved")
        self.assertFalse(Path(str(self.old) + ".lui-previous").exists())

    def test_installer_refuses_to_destroy_existing_backup(self):
        backup = Path(str(self.old) + ".lui-previous")
        backup.mkdir()
        (backup / "recovery").write_text("recoverable")
        self.probe("install", self.new, self.old, success=False)
        self.assertTrue((self.old / "removed.txt").exists())
        self.assertEqual((backup / "recovery").read_text(), "recoverable")

    def test_failed_start_can_restore_the_previous_complete_tree(self):
        self.probe("rollback", self.new, self.old)
        self.assertTrue((self.old / "removed.txt").exists())
        self.assertFalse((self.old / "added.txt").exists())
        self.assertFalse(Path(str(self.old) + ".lui-previous").exists())

    def test_builder_rejects_symlinks_and_insecure_update_feeds(self):
        config = self.directory / "config.json"
        config.write_text(json.dumps(dict(self.config, updates=dict(url="http://example.com", public_key="00" * 32))))
        with self.assertRaises(ValueError):
            desktop.configuration(config)
        if os.name != "nt":
            (self.new / "linked").symlink_to(self.old)
            with self.assertRaises(ValueError):
                desktop.write_package(self.new, self.directory / "package")

    def test_release_refuses_wrong_signing_key(self):
        config = dict(self.config, build=2, updates=dict(url="https://example.com/updates", public_key="00" * 32))
        (self.new / "lui-desktop.json").write_text(json.dumps(config))
        with self.assertRaises(ValueError):
            self.feed()
        self.assertFalse((self.directory / "release/update-linux-amd64.json").exists())

    def test_wasm_is_an_explicit_boolean_build_capability(self):
        config = self.directory / "config.json"
        for web in [{"wasm": True}, {"wasm": False}, {}]:
            config.write_text(json.dumps(dict(self.config, web=web)))
            self.assertEqual(desktop.configuration(config)["web"], web)
        for web in [True, {"wasm": "true"}, {"wasm": 1}, {"wasn": True}]:
            config.write_text(json.dumps(dict(self.config, web=web)))
            with self.assertRaises(ValueError):
                desktop.configuration(config)

    def test_public_artifact_constructor_cannot_bypass_validation(self):
        invalid = self.directory / "invalid.ml"
        invalid.write_text('let artifact : Lui_desktop_update.artifact = {url="http://bad"; size=0; sha256=""}\n')
        result = subprocess.run(["opam", "exec", "--", "ocamlfind", "ocamlopt", "-I", str(self.work),
                                 "-c", str(invalid)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("private", result.stderr)


if __name__ == "__main__":
    unittest.main()
