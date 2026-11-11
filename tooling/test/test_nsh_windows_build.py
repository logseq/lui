"""Builder guards and fresh-archive orchestration; not Windows qualification."""
import contextlib
import importlib.util
import io
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
                root = Path(directory)
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

    def test_export_verification_rejects_a_library_without_the_required_abi(self):
        with patch.object(builder.ctypes, "CDLL", return_value=object()):
            with self.assertRaisesRegex(ValueError, "lui_ocaml_start"):
                builder.verify_exports(Path("not-loaded-by-this-mocked-test.dll"))


if __name__ == "__main__":
    unittest.main()
