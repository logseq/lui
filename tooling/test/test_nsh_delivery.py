"""Exercise complete desktop archives, source pins and signing order."""
import argparse
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

MODULE = Path(__file__).resolve().parents[1] / "nsh_delivery.py"
spec = importlib.util.spec_from_file_location("nsh_delivery", MODULE)
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)


def binary(path, target, architecture="aarch64"):
    data = bytearray(128)
    if target == "macos":
        data[:4] = b"\xcf\xfa\xed\xfe"
        struct.pack_into("<I", data, 4, {"aarch64": 0x0100000C, "x86_64": 0x01000007}[architecture])
    elif target == "linux":
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", data, 18, {"aarch64": 183, "x86_64": 62}[architecture])
    else:
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 60, 64)
        data[64:68] = b"PE\0\0"
        struct.pack_into("<H", data, 68, {"aarch64": 0xAA64, "x86_64": 0x8664}[architecture])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(0o755)
    return path


def arguments(library):
    return argparse.Namespace(library=library, dependency=[], asset=[], macos_identity=None,
                              entitlements=None, notary_profile=None, windows_thumbprint=None,
                              timestamp_url=None, signtool="signtool")


class DeliveryTests(unittest.TestCase):
    def test_cli_version_accepts_checkout_revision_and_rejects_other_builds(self):
        source = {"revision": "028574b7de9ee25a7c6f60660ef72fcb8790a27e"}
        for observed in ("nsh 0.5.0", "nsh 0.5.0 (028574b)",
                         "nsh 0.5.0 (028574b7de9ee25a7c6f60660ef72fcb8790a27e)"):
            delivery.require_cli_version(observed, "0.5.0", source)
        for observed in ("nsh 0.5.1 (028574b)", "nsh 0.5.0 (a4c64cb)",
                         "nsh 0.5.0 (028574b-dirty)", "other 0.5.0", "nsh 0.5.0 extra"):
            with self.subTest(observed=observed), self.assertRaises(delivery.DeliveryError):
                delivery.require_cli_version(observed, "0.5.0", source)

    def test_macos_children_disable_release_strip_and_preserve_build_settings(self):
        inherited = {"CARGO_PROFILE_RELEASE_STRIP": "debuginfo",
                     "CARGO_PROFILE_RELEASE_OPT_LEVEL": "3", "RUSTFLAGS": "-Dwarnings"}
        for system in ("Darwin", "Linux", "Windows"):
            with self.subTest(system=system), patch.dict(os.environ, inherited), \
                    patch.object(delivery.platform, "system", return_value=system), \
                    patch.object(delivery.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "fixture output\n")) as child:
                self.assertEqual(delivery.run(["nsh", "package", "app with spaces"], capture=True), "fixture output")
                environment = child.call_args.kwargs["env"]
                self.assertEqual(environment["CARGO_PROFILE_RELEASE_STRIP"], "none" if system == "Darwin" else "debuginfo")
                self.assertEqual(environment["CARGO_PROFILE_RELEASE_OPT_LEVEL"], "3")
                self.assertEqual(environment["RUSTFLAGS"], "-Dwarnings")
                self.assertEqual(os.environ["CARGO_PROFILE_RELEASE_STRIP"], "debuginfo")
                self.assertEqual(child.call_args.args[0], ["nsh", "package", "app with spaces"])

    def test_final_archives_include_ocaml_dependencies_assets_and_receipt(self):
        for target in ("macos", "linux", "windows"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                output = directory / "output"
                output.mkdir()
                config = dict(name="LUI Test", id="com.logseq.test", version="1.2.3", build=7)
                root, executable, resources = delivery.package_layout(output, config, target)
                binary(executable, target)
                library = binary(directory / "outside checkout/应用 library", target)
                dependency = binary(directory / "outside checkout/dependency.bin", target)
                asset = directory / "outside checkout/文档.txt"
                asset.write_text("Complete application resources", encoding="utf-8")
                args = arguments(library)
                args.dependency = [dependency]
                args.asset = [(asset, "localized/文档.txt")]
                calls = []
                with patch.object(delivery, "run", side_effect=lambda command, **_: (calls.append([str(part) for part in command]) or "")) as _mock_run:
                    delivery.finalize(root, executable, resources, config, target, {"aarch64"}, args,
                                      {"schemaVersion": 1, "nsh": {"revision": "a" * 40}})
                    archives = delivery.archive_package(root, output, config, target, {"aarch64"})
                self.assertEqual(len(archives), 1)
                if target == "windows":
                    with zipfile.ZipFile(archives[0]) as archive:
                        names = archive.namelist()
                        read = archive.read
                        library_name = f"{root.name}/lui/lui_app.dll"
                        self.assertIn(library_name, names)
                        self.assertEqual(read(library_name), library.read_bytes())
                        self.assertEqual(read(f"{root.name}/lui/assets/localized/文档.txt"), asset.read_bytes())
                        receipt = json.loads(read(f"{root.name}/lui/{delivery.RECEIPT}"))
                else:
                    with tarfile.open(archives[0]) as archive:
                        prefix = f"{root.name}/" + ("Contents/Resources/lui" if target == "macos" else "lui")
                        library_name = "liblui_app.dylib" if target == "macos" else "liblui_app.so"
                        self.assertEqual(archive.extractfile(f"{prefix}/{library_name}").read(), library.read_bytes())
                        self.assertEqual(archive.extractfile(f"{prefix}/dependency.bin").read(), dependency.read_bytes())
                        self.assertEqual(archive.extractfile(f"{prefix}/assets/localized/文档.txt").read(), asset.read_bytes())
                        receipt = json.load(archive.extractfile(f"{prefix}/{delivery.RECEIPT}"))
                self.assertEqual(receipt["application"]["version"], "1.2.3")
                self.assertEqual(receipt["ocaml"]["librarySha256"], delivery.digest(library))
                self.assertNotIn(str(directory), json.dumps(receipt))
                if target == "macos":
                    signed = [command[-1] for command in calls if command[0] == "codesign" and "--sign" in command]
                    self.assertEqual(signed[-1], str(root))
                    self.assertEqual(signed[-2], str(executable))
                    self.assertIn("--verify", calls[-1])

    @unittest.skipUnless(sys.platform == "darwin", "Requires the macOS C toolchain and codesign")
    def test_native_macos_fixture_launches_and_verifies_after_relocation_and_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            config = dict(name="Native Fixture", id="com.logseq.fixture", version="1.0.0", build=1)
            root, executable, resources = delivery.package_layout(directory, config, "macos")
            executable.parent.mkdir(parents=True)
            with (root / "Contents/Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleExecutable": executable.name,
                               "CFBundleIdentifier": config["id"],
                               "CFBundleName": config["name"],
                               "CFBundlePackageType": "APPL"}, file)
            source = directory / "fixture.c"
            dependency_source = directory / "dependency.c"
            dependency_source.write_text("int fixture_dependency(void) { return 7; }\n")
            dependency = directory / "development only/libdependency.dylib"
            dependency.parent.mkdir()
            subprocess.run(["cc", "-dynamiclib", str(dependency_source), "-o", str(dependency)], check=True)
            source.write_text("extern int fixture_dependency(void);\nint fixture(void) { return fixture_dependency(); }\n")
            library = directory / "original-library.dylib"
            subprocess.run(["cc", "-dynamiclib", str(source), str(dependency), "-o", str(library)], check=True)
            source.write_text('#include <dlfcn.h>\nint main(int argc, char **argv) { if (argc != 2) return 1; void *handle = dlopen(argv[1], RTLD_NOW); if (!handle) return 2; int (*fixture)(void) = dlsym(handle, "fixture"); return fixture && fixture() == 7 ? 0 : 3; }\n')
            subprocess.run(["cc", str(source), "-o", str(executable)], check=True)
            wanted = {delivery.host_architecture()}
            args = arguments(library)
            args.dependency = [dependency]
            result = delivery.finalize(root, executable, resources, config, "macos", wanted,
                                       args, {"schemaVersion": 1})
            self.assertEqual(result, "ad-hoc")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(root)], check=True)
            outside = directory / "outside checkout"
            outside.mkdir()
            library.unlink()
            dependency.unlink()
            subprocess.run([str(executable), str(resources / "liblui_app.dylib")], cwd=outside, check=True)
            archive = delivery.archive_package(root, directory, config, "macos", wanted)[0]
            with tarfile.open(archive) as file:
                self.assertIn("Native Fixture.app/Contents/Resources/lui/liblui_app.dylib", file.getnames())

    def test_architecture_mismatch_fails_before_resources_are_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            config = dict(name="Test Application", id="com.logseq.test", version="1.0.0", build=1)
            root, executable, resources = delivery.package_layout(directory, config, "linux")
            binary(executable, "linux")
            library = binary(directory / "source/liblui_app.so", "linux", "x86_64")
            with self.assertRaisesRegex(delivery.DeliveryError, "requested architectures"):
                delivery.finalize(root, executable, resources, config, "linux", {"aarch64"},
                                  arguments(library), {})
            self.assertFalse(resources.exists())
            self.assertEqual(list(directory.glob("*.tar.gz")), [])

    def test_signing_and_notarization_finish_before_archive_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            root = directory / "LUI.app"
            executable = root / "Contents/MacOS/LUI"
            library = root / "Contents/Resources/lui/liblui_app.dylib"
            binary(executable, "macos")
            binary(library, "macos")
            args = arguments(library)
            args.macos_identity = "Developer ID Application: Test"
            args.notary_profile = "test-profile"
            args.entitlements = directory / "app.plist"
            commands = []

            def execute(command, **_):
                commands.append([str(part) for part in command])
                if command[:3] == ["xcrun", "stapler", "staple"]:
                    (root / "stapled-fixture").write_text("ticket")

            with patch.object(delivery, "run", side_effect=execute):
                self.assertEqual(delivery.sign_macos(root, executable, [library], args), "developer-id")
            signed = [command for command in commands if command[0] == "codesign" and "--sign" in command]
            self.assertEqual([command[-1] for command in signed], [str(library), str(executable), str(root)])
            self.assertIn("runtime", signed[-1])
            self.assertIn("--entitlements", signed[-1])
            self.assertLess(commands.index(next(c for c in commands if c[:3] == ["xcrun", "notarytool", "submit"])),
                            commands.index(next(c for c in commands if c[:3] == ["xcrun", "stapler", "staple"])))
            archive = delivery.archive_package(root, directory, dict(name="LUI", version="1.0.1"), "macos", {"aarch64"})[0]
            with tarfile.open(archive) as file:
                self.assertEqual(file.extractfile("LUI.app/stapled-fixture").read(), b"ticket")

    def test_registry_or_wrong_revision_cannot_enter_generated_runner(self):
        source = {"repository": "https://github.com/logseq/nsh", "revision": "a" * 40}
        core = {"name": "nsh-core", "source": f"git+{source['repository']}?rev={source['revision']}#{source['revision']}"}
        engine = dict(core, name="nsh-engine")
        self.assertEqual(delivery.verify_graph({"packages": [core, engine]}, source), ["nsh-core", "nsh-engine"])
        for wrong in ("registry+https://github.com/rust-lang/crates.io-index",
                      f"git+{source['repository']}#{'b' * 40}",
                      f"git+https://github.com/longbridge/nsh#{source['revision']}"):
            with self.subTest(source=wrong), self.assertRaises(delivery.DeliveryError):
                delivery.verify_graph({"packages": [core, dict(engine, source=wrong)]}, source)

    def test_floating_or_mixed_manifest_sources_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            for source in ('branch = "fork/logseq"', 'rev = "abc123"'):
                (app / "Cargo.toml").write_text('[dependencies]\nnsh-core = { git="https://github.com/logseq/nsh", ' + source + ' }\n')
                with self.assertRaises(delivery.DeliveryError):
                    delivery.pinned_source(app)
            (app / "Cargo.toml").write_text('[dependencies]\nnsh-core = {git="https://github.com/logseq/nsh", rev="' + 'a' * 40 + '"}\nnsh-engine = "0.5.0"\n')
            with self.assertRaisesRegex(delivery.DeliveryError, "Git pin"):
                delivery.pinned_source(app)

    def test_package_uses_absolute_staging_and_rejects_changed_verified_inputs(self):
        for mutation in (None, "library", "Cargo.lock", "nsh.json", "src/lib.rs", "build.rs", "generated-lock", "registry"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                app = directory / "app"
                app.mkdir()
                revision = "a" * 40
                (app / "Cargo.toml").write_text('[dependencies]\nnsh-core={git="https://github.com/logseq/nsh",rev="' + revision + '"}\n')
                (app / "Cargo.lock").write_text("version=4\n")
                (app / "src").mkdir()
                (app / "src/lib.rs").write_text("pub fn application() {}\n")
                (app / "build.rs").write_text("fn main() {}\n")
                config = dict(name="Test Application", id="com.logseq.test", version="1.0.0", build=1)
                (app / "nsh.json").write_text(json.dumps(config))
                library = binary(directory / "original library.so", "linux")
                expected = delivery.digest(library)
                Path(str(library) + ".lui-build.json").write_text(json.dumps({"artifactDigest": expected, "files": {"src/app.ml": "f" * 64}}))
                args = arguments(library)
                args.app = app
                args.output = Path("relative release")
                args.target = "linux"
                args.arch = "aarch64"
                args.cargo = "fixture-cargo"
                args.node = "fixture-node"
                args.cli_directory = directory / "toolchain"
                args.iscc = None
                metadata = {"packages": [{"name": name, "source": f"git+https://github.com/logseq/nsh#{revision}"} for name in ("nsh-core", "nsh-engine")]}

                def metadata_for(_cargo, manifest):
                    result = {"packages": list(metadata["packages"])}
                    result["packages"].append({"name": "serde", "version": "1.0.1" if mutation == "registry" and ".nsh" in str(manifest) else "1.0.0", "source": "registry+https://github.com/rust-lang/crates.io-index"})
                    return result

                def execute(command, **_):
                    if len(command) > 1 and command[1] == "build":
                        generated = app / ".nsh/rust"
                        self.assertEqual((generated / "Cargo.lock").read_bytes(), (app / "Cargo.lock").read_bytes(), "Generated runner must start from the tested app lock")
                        generated.mkdir(parents=True, exist_ok=True)
                        (generated / "Cargo.toml").write_text("[workspace]\n")
                        (generated / "Cargo.lock").write_text("version=4\n")
                    if len(command) > 1 and command[1] == "package":
                        staged = Path(command[command.index("-o") + 1])
                        self.assertTrue(staged.is_absolute(), "NSH package runs from another working directory")
                        root, executable, _ = delivery.package_layout(staged, config, "linux")
                        binary(executable, "linux")
                        if mutation == "library":
                            library.write_bytes(library.read_bytes() + b"rebuilt after verification")
                        elif mutation == "generated-lock":
                            generated_lock = app / ".nsh/rust/Cargo.lock"
                            generated_lock.write_bytes(generated_lock.read_bytes() + b"# updated during packaging")
                        elif mutation:
                            path = app / mutation
                            path.write_bytes(path.read_bytes() + b" ")

                previous = Path.cwd()
                try:
                    os.chdir(directory)
                    with patch.object(delivery, "host_target", return_value="linux"), patch.object(delivery, "host_architecture", return_value="aarch64"), patch.object(delivery, "verified_cli", return_value=(directory / "nsh", {"sha256": "c" * 64})), patch.object(delivery, "cargo_metadata", side_effect=metadata_for), patch.object(delivery, "run", side_effect=execute), patch("builtins.print"):
                        if mutation:
                            with self.assertRaisesRegex(delivery.DeliveryError, "changed|registry dependencies"):
                                delivery.package(args)
                        else:
                            delivery.package(args)
                finally:
                    os.chdir(previous)
                receipts = list((directory / "relative release").glob("*-receipt.json"))
                if mutation:
                    self.assertEqual(receipts, [])
                    self.assertEqual(list((directory / "relative release").glob("*.tar.gz")), [])
                else:
                    self.assertEqual(len(receipts), 1)
                    result = json.loads(receipts[0].read_text())
                    self.assertEqual(result["ocamlArtifactSha256"], expected)
                    self.assertIn("src/lib.rs", result["applicationSourceHashes"])
                    self.assertIn("build.rs", result["applicationSourceHashes"])
                    self.assertTrue(list((directory / "relative release").glob("*.tar.gz")))

    def test_changed_checkout_during_cli_build_cannot_receive_a_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            checkout = directory / "nsh"
            checkout.mkdir()
            (checkout / "Cargo.toml").write_text('[workspace.package]\nversion="0.5.0"\n')
            (checkout / ".gitignore").write_text("/target/\n")
            subprocess.run(["git", "init", "--quiet", str(checkout)], check=True)
            subprocess.run(["git", "-C", str(checkout), "add", "Cargo.toml", ".gitignore"], check=True)
            subprocess.run(["git", "-C", str(checkout), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "--quiet", "-m", "Fixture"], check=True)
            revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
            marker = checkout / ".cargo-ok"
            marker.touch()
            delivery.verify_checkout(checkout, {"revision": revision})
            marker.write_text("not a Cargo completion marker")
            with self.assertRaisesRegex(delivery.DeliveryError, "uncommitted"):
                delivery.verify_checkout(checkout, {"revision": revision})
            marker.write_text("")
            app = directory / "app"
            app.mkdir()
            (app / "Cargo.toml").write_text('[dependencies]\nnsh-core={git="https://github.com/logseq/nsh",rev="' + revision + '"}\n')
            artifact = checkout / "target/release" / ("nsh.exe" if os.name == "nt" else "nsh")
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b"fixture CLI")
            args = argparse.Namespace(app=app, checkout=checkout, destination=directory / "installed CLI", cargo="fixture-cargo")
            original_run = delivery.run

            def execute(command, **kwargs):
                if command[0] == "fixture-cargo":
                    if command[1] == "build":
                        with (checkout / "Cargo.toml").open("a") as file:
                            file.write("# modified during CLI compilation\n")
                        return None
                    return json.dumps({"target_directory": str(checkout / "target")})
                if str(command[-1]) == "--version":
                    return "nsh 0.5.0"
                return original_run(command, **kwargs)

            with patch.object(delivery, "run", side_effect=execute), self.assertRaisesRegex(delivery.DeliveryError, "uncommitted"):
                delivery.setup(args)
            self.assertFalse((args.destination / delivery.CLI_RECEIPT).exists())
            self.assertFalse((args.destination / artifact.name).exists())

    def test_changed_copy_is_rejected_before_signing_or_receipts(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            config = dict(name="Test Application", id="com.logseq.test", version="1.0.0", build=1)
            root, executable, resources = delivery.package_layout(directory, config, "linux")
            binary(executable, "linux")
            library = binary(directory / "input/library.so", "linux")
            expected = delivery.digest(library)
            original_copy = delivery.shutil.copy2

            def copy(source, destination):
                result = original_copy(source, destination)
                Path(destination).write_bytes(Path(destination).read_bytes() + b"changed during copy")
                return result

            with patch.object(delivery.shutil, "copy2", side_effect=copy), self.assertRaisesRegex(delivery.DeliveryError, "Copied OCaml"):
                delivery.finalize(root, executable, resources, config, "linux", {"aarch64"},
                                  arguments(library), {"ocamlArtifactSha256": expected})
            self.assertFalse((resources / delivery.RECEIPT).exists())

    def test_manifest_refuses_missing_or_modified_complete_application_receipts(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            app = directory / "app"
            app.mkdir()
            revision = "a" * 40
            (app / "Cargo.toml").write_text('[dependencies]\nnsh-core = {git="https://github.com/logseq/nsh",rev="' + revision + '"}\n')
            config = dict(name="Application", id="com.logseq.test", version="1.0.0", build=1)
            (app / "nsh.json").write_text(json.dumps(config))
            archive = directory / "Application-1.0.0-linux-aarch64.tar.gz"
            archive.write_bytes(b"complete archive fixture")
            args = argparse.Namespace(app=app, cli_directory=directory, archives=[archive],
                                      key=directory / "test-only.secret", output=directory,
                                      notes=None, base_url=None)
            source = delivery.pinned_source(app)
            commands = []
            with patch.object(delivery, "verified_cli", return_value=(directory / "nsh", {})), patch.object(delivery, "run", side_effect=lambda command, **_: commands.append(command)):
                with self.assertRaisesRegex(delivery.DeliveryError, "complete-application"):
                    delivery.manifest(args)
                self.assertEqual(commands, [])
                receipt = {"nsh": source, "archives": {archive.name: delivery.digest(archive)}}
                (directory / "com.logseq.test-1.0.0-linux-receipt.json").write_text(json.dumps(receipt))
                delivery.manifest(args)
                self.assertEqual(commands[-1][1], "update-manifest")
                archive.write_bytes(b"modified after packaging")
                with self.assertRaisesRegex(delivery.DeliveryError, "complete-application"):
                    delivery.manifest(args)
                self.assertEqual(len(commands), 1)

    def test_invalid_release_identifiers_cannot_escape_output_paths(self):
        good = dict(name="LUI Desktop", id="com.logseq.lui", version="1.2.3-beta.1+build.7", build=1)
        delivery.validate_application(good)
        for key, value in (("name", "../Application"), ("id", "../application"),
                           ("version", "../../outside"), ("version", "1.2.3-.."),
                           ("version", "1.2.3-01"), ("build", True)):
            with self.subTest(key=key, value=value), self.assertRaises(delivery.DeliveryError):
                delivery.validate_application(dict(good, **{key: value}))

    def test_assets_cannot_escape_package_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            library = directory / "lib.so"
            library.write_bytes(b"library")
            for destination in ("../outside", "/outside", "C:\\outside", "C:outside"):
                with self.subTest(destination=destination), self.assertRaises(delivery.DeliveryError):
                    delivery.copy_payload(directory / "resources", library, [], [(library, destination)], "linux")
            self.assertFalse((directory / "outside").exists())

    def test_authenticode_signs_and_verifies_every_code_file(self):
        args = arguments(Path("library.dll"))
        args.windows_thumbprint = "test-certificate-thumbprint"
        args.timestamp_url = "https://timestamp.example.test"
        commands = []
        with patch.object(delivery, "run", side_effect=lambda command, **_: commands.append(command)):
            result = delivery.sign_windows([Path("Application.exe"), Path("library.dll"), Path("Application-setup.exe")], args)
        self.assertEqual(result, "authenticode")
        self.assertEqual(len(commands), 6)
        self.assertEqual([c[1] for c in commands], ["sign", "verify"] * 3)
        self.assertEqual([c[-1] for c in commands[::2]], [Path("Application.exe"), Path("library.dll"), Path("Application-setup.exe")])


if __name__ == "__main__":
    unittest.main()
