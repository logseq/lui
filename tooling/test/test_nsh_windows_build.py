"""Builder guards and fresh-archive orchestration; not Windows qualification."""
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("nsh_windows_build", ROOT / "tooling/build_nsh_windows.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

CONFIG = {"version": "5.5.1", "os_type": "Win32", "system": "mingw64",
          "architecture": "amd64", "ext_dll": ".dll", "ext_obj": ".o"}

FIXTURE_SPEC = importlib.util.spec_from_file_location(
    "nsh_fixture_build", ROOT / "platform/nsh/tests/fixtures/build_virtual.py")
fixtures = importlib.util.module_from_spec(FIXTURE_SPEC)
FIXTURE_SPEC.loader.exec_module(fixtures)


class WindowsBuilderTests(unittest.TestCase):
    def test_host_guard_rejects_cross_compilation_before_running_tools(self):
        with patch.object(builder.platform, "system", return_value="Linux"), \
                patch.object(builder, "execute") as execute:
            with self.assertRaisesRegex(ValueError, "requires native Windows"):
                builder.native_config()
            execute.assert_not_called()

    def test_native_host_rejects_a_cygwin_target(self):
        config = {**CONFIG, "os_type": "Cygwin"}
        text = "\n".join(f"{key}: {value}" for key, value in config.items())
        with patch.object(builder.platform, "system", return_value="Windows"), \
                patch.object(builder, "execute", return_value=text):
            with self.assertRaisesRegex(ValueError, "native Win32"):
                builder.native_config()

    def test_fresh_build_produces_every_archive_before_native_link_and_records_exports(self):
        for application in builder.APPLICATIONS:
            with self.subTest(application=application), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                commands = []

                def execute(command, **_):
                    command = [str(part) for part in command]
                    commands.append(command)
                    if command[3:5] == ["dune", "build"]:
                        for target in command[5:]:
                            path = root / "_build/default" / target
                            path.parent.mkdir(parents=True, exist_ok=True)
                            path.touch()
                    if "-output-complete-obj" in command:
                        archives = [Path(part) for part in command if part.endswith(".cmxa")]
                        self.assertEqual(len(archives), 3)
                        self.assertTrue(all(path.is_file() for path in archives))
                        self.assertEqual(Path(command[-1]).suffix, ".dll")
                        self.assertFalse({"-fPIC", "-lpthread", "-ldl", "-shared"}.intersection(command))

                with patch.object(builder, "ROOT", root), \
                        patch.object(builder, "native_config", return_value=CONFIG), \
                        patch.object(builder, "execute", side_effect=execute), \
                        patch.object(builder, "verify_exports", return_value=["lui_ocaml_start"]) as verify, \
                        patch.object(builder.shutil, "which", return_value=None), \
                        contextlib.redirect_stderr(io.StringIO()):
                    library = builder.build(application)
                self.assertEqual(len(commands), 3)
                self.assertIn("-c", commands[1])
                self.assertIn("ocamlopt", commands[1])
                verify.assert_called_once_with(library)
                self.assertTrue((library.parent / "ocaml-toolchain.json").is_file())

    def test_native_link_rejects_non_dll_output_before_running_a_compiler(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, "execute") as execute:
            with self.assertRaisesRegex(ValueError, "requires a .dll"):
                builder.link_native_dll(Path(directory).resolve() / "fixture_complete.o", [], config=CONFIG)
            execute.assert_not_called()

    def test_native_link_uses_configured_object_suffix_and_keeps_space_paths_atomic(self):
        with tempfile.TemporaryDirectory(prefix="lui native link ") as directory:
            root = Path(directory).resolve()
            library = root / "application with spaces" / "lui_fixture.dll"
            inputs = [root / "lui library.cmxa", root / "fixture source.ml"]
            commands = []
            with patch.object(builder, "ROOT", root), \
                    patch.object(builder, "execute", side_effect=lambda command, **_: commands.append(list(map(str, command)))), \
                    patch.object(builder, "verify_exports", return_value=["lui_ocaml_load"]):
                builder.link_native_dll(library, inputs, config={**CONFIG, "ext_obj": ".obj"})
            compile_c, link = commands
            self.assertEqual(compile_c[:4], ["opam", "exec", "--", "ocamlopt"])
            self.assertIn("-c", compile_c)
            c_object = Path(compile_c[compile_c.index("-o") + 1])
            self.assertEqual(c_object.suffix, ".obj")
            self.assertEqual(link[-1], str(library))
            self.assertTrue(all(str(path) in link for path in [*inputs, c_object]))
            self.assertFalse({"cc", "-fPIC", "-shared", "-lpthread", "-ldl", "-lm"}.intersection(compile_c + link))
            evidence = json.loads((library.parent / "ocaml-toolchain.json").read_text())
            self.assertEqual(evidence["compiler"]["ext_obj"], ".obj")
            self.assertEqual(evidence["exports"], ["lui_ocaml_load"])
            self.assertIn("runtime and package tests run separately", evidence["qualification"])

    def test_export_verification_rejects_a_library_without_the_required_abi(self):
        with patch.object(builder.ctypes, "CDLL", return_value=object()):
            with self.assertRaisesRegex(ValueError, "lui_ocaml_start"):
                builder.verify_exports(Path("not-loaded-by-this-mocked-test.dll"))


class FixtureBuilderTests(unittest.TestCase):
    def test_unsupported_host_is_rejected_before_any_tool_invocation(self):
        with patch.object(fixtures.platform, "system", return_value="OtherOS"), \
                patch.object(fixtures, "execute") as execute:
            with self.assertRaisesRegex(SystemExit, "require native"):
                fixtures.build_fixture("image")
            execute.assert_not_called()

    def test_windows_fixture_rejects_cygwin_before_dune_or_copying_sources(self):
        config = {**CONFIG, "os_type": "Cygwin"}
        text = "\n".join(f"{key}: {value}" for key, value in config.items())
        with patch.object(fixtures.platform, "system", return_value="Windows"), \
                patch.object(builder, "execute", return_value=text), \
                patch.dict(sys.modules, {"build_nsh_windows": builder}), \
                patch.object(fixtures.sys, "path", list(sys.path)), \
                patch.object(fixtures, "execute") as execute:
            with self.assertRaisesRegex(ValueError, "native Win32"):
                fixtures.build_fixture("image")
            execute.assert_not_called()

    def build_mocked(self, root, target, fixture="image", version=None):
        script = root / "platform/nsh/tests/fixtures/build_virtual.py"
        script.parent.mkdir(parents=True)
        script.write_text("# Fixture builder input\n")
        script.with_name(f"{fixture}_app.ml").write_text('let version = "__LUI_UPGRADE_VERSION__"\n')
        driver = root / "_build/default/.ppx/driver with spaces/ppx.exe"
        driver.parent.mkdir(parents=True)
        driver.touch()
        commands = []

        def execute(command, **_):
            command = list(map(str, command))
            commands.append(command)
            if command[3:5] == ["dune", "build"]:
                for name in command[5:]:
                    archive = root / "_build/default" / name
                    archive.parent.mkdir(parents=True, exist_ok=True)
                    archive.touch()
            if "-output-complete-obj" in command:
                self.assertTrue((root / "_build/default/src/lui.cmxa").is_file())
                self.assertTrue(any(Path(part).is_file() for part in command if part.endswith("_app.ml")))
            if "-o" in command:
                Path(command[command.index("-o") + 1]).write_bytes(b"mock object, not a qualified binary")

        with patch.object(fixtures, "ROOT", root), \
                patch.object(fixtures, "__file__", str(script)), \
                patch.object(fixtures.platform, "system", return_value=target), \
                patch.object(fixtures, "execute", side_effect=execute), \
                patch.object(fixtures.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "lui_ppx\n", "")), \
                patch.object(fixtures.subprocess, "check_output", return_value=str(root / "ocaml include")), \
                patch.object(builder, "ROOT", root), \
                patch.object(builder, "native_config", return_value=CONFIG) as config, \
                patch.object(builder, "execute", side_effect=execute), \
                patch.object(builder, "verify_exports", return_value=["lui_ocaml_load"]), \
                patch.dict(sys.modules, {"build_nsh_windows": builder}), \
                patch.object(fixtures.sys, "path", list(sys.path)):
            library = fixtures.build_fixture(fixture, version=version)
        self.assertEqual(config.call_count, int(target == "Windows"))
        return library, driver, commands

    def test_windows_fixture_links_native_dll_with_quoted_ppx_and_receipt_inputs(self):
        for fixture in ("image", "virtual", "clock", "tabs", "navigation", "upgrade"):
            with self.subTest(fixture=fixture), tempfile.TemporaryDirectory(prefix="lui fixture ") as directory:
                root = Path(directory).resolve()
                library, driver, commands = self.build_mocked(root, "Windows", fixture,
                                                              "1.0.0" if fixture == "upgrade" else None)
                self.assertEqual(library.name, f"lui_{fixture}.dll")
                self.assertIn("-c", commands[1])
                link = next(command for command in commands if "-output-complete-obj" in command)
                ppx = link[link.index("-ppx") + 1]
                self.assertEqual(ppx, f'"{driver}" --as-ppx')
                self.assertEqual(link[-1], str(library))
                self.assertFalse({"cc", "-fPIC", "-shared", "-lpthread", "-ldl", "-lm"}.intersection(
                    part for command in commands for part in command))
                self.assertTrue((library.parent / "ocaml-toolchain.json").is_file())
                if fixture in ("image", "tabs", "navigation"):
                    receipt = commands[-1]
                    self.assertIn("tooling/build_nsh_windows.py", receipt)
                    self.assertIn("platform/nsh/tests/fixtures/build_virtual.py", [part.replace("\\", "/") for part in receipt])
                    self.assertIn(f"python platform/nsh/tests/fixtures/build_virtual.py --fixture {fixture}", receipt)
                if fixture == "upgrade":
                    self.assertEqual((library.parent / "upgrade_app.ml").read_text(), 'let version = "1.0.0"\n')

    def test_unix_fixtures_keep_pic_platform_links_and_posix_ppx_quoting(self):
        for target, suffix in (("Darwin", ".dylib"), ("Linux", ".so")):
            with self.subTest(target=target), tempfile.TemporaryDirectory(prefix="lui fixture ") as directory:
                root = Path(directory).resolve()
                library, driver, commands = self.build_mocked(root, target)
                self.assertEqual(library.name, "liblui_image" + suffix)
                ocaml = next(command for command in commands if "-output-complete-obj" in command)
                self.assertEqual(ocaml[ocaml.index("-ppx") + 1], f"'{driver}' --as-ppx")
                self.assertEqual("-runtime-variant" in ocaml, target == "Linux")
                native = next(command for command in commands if command[0] == "cc")
                self.assertTrue({"-fPIC", "-shared", "-lpthread"}.issubset(native))
                self.assertEqual("-ldl" in native, target == "Linux")
                self.assertEqual("-lm" in native, target == "Linux")
                self.assertNotIn("tooling/build_nsh_windows.py", commands[-1])
                self.assertIn("python3 platform/nsh/tests/fixtures/build_virtual.py --fixture image", commands[-1])


if __name__ == "__main__":
    unittest.main()
