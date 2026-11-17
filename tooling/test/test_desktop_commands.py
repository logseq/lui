"""Command registry behavior and compiler contracts on native and Melange targets."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DesktopCommands(unittest.TestCase):
    def test_native_registry_and_compile_failure_contracts(self):
        with tempfile.TemporaryDirectory(prefix="lui-command-tests-") as temporary:
            work = Path(temporary)
            for name, directory in [("lui_command", ROOT / "src"), ("lui_desktop_commands", ROOT / "platform/desktop")]:
                for suffix in (".mli", ".ml"):
                    shutil.copy2(directory / (name + suffix), work)
            shutil.copy2(ROOT / "platform/desktop/test/commands_probe.ml", work)
            build = ["opam", "exec", "--", "ocamlfind", "ocamlopt", "-thread", "-package", "unix,threads,yojson", "-linkpkg"]
            subprocess.run(build + ["lui_command.mli", "lui_command.ml", "lui_desktop_commands.mli",
                            "lui_desktop_commands.ml", "commands_probe.ml", "-o", "probe"], cwd=work, check=True)
            result = subprocess.run([str(work / "probe")], capture_output=True, text=True, timeout=10, check=True)
            self.assertIn("commands passed", result.stdout)
            prefix = '''let name = Result.get_ok (Lui_command.Name.of_string "app.echo")
let echo = Lui_command.v ~name ~request:Lui_command.Codec.string ~response:Lui_command.Codec.string
'''
            cases = [
                (prefix + 'let _ = Lui_desktop_commands.handle echo (fun value -> Ok value)\n', True),
                (prefix + 'let _ = Lui_desktop_commands.handle echo (fun _ -> Ok 3l)\n', False),
                ('let _ = Lui_command.v ~name:"app.echo" ~request:Lui_command.Codec.string ~response:Lui_command.Codec.string\n', False),
            ]
            for index, (source, valid) in enumerate(cases):
                probe = work / f"contract_{index}.ml"
                probe.write_text(source)
                result = subprocess.run(build + ["-c", probe.name], cwd=work, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, valid, result.stdout + result.stderr)
                if not valid:
                    self.assertIn("but an expression was expected", result.stderr)

    def test_melange_invocation_types(self):
        subprocess.run(["opam", "exec", "--", "dune", "build", "--profile", "release", "@web"], cwd=ROOT, check=True)
        includes = [ROOT / "_build/default/src/.lui.objs/melange",
                    ROOT / "_build/default/platform/web/melange/.lui_web_dom.objs/melange"]
        compiler = ["opam", "exec", "--", "melc"]
        for include in includes:
            compiler.extend(["-I", str(include)])
        compiler.extend(["-I", subprocess.check_output(["opam", "exec", "--", "ocamlfind", "query", "melange.js"], text=True).strip()])
        with tempfile.TemporaryDirectory(prefix="lui-command-melange-") as temporary:
            work = Path(temporary)
            prefix = '''let name = Result.get_ok (Lui_command.Name.of_string "app.echo")
let echo = Lui_command.v ~name ~request:Lui_command.Codec.string ~response:Lui_command.Codec.int32
'''
            cases = [(prefix + 'let _ = Lui_web_desktop.invoke echo "hello"\n', True),
                     (prefix + 'let _ = Lui_web_desktop.invoke echo 3l\n', False),
                     ('let _ = Lui_web_desktop.invoke "app.echo" "hello"\n', False)]
            for index, (source, valid) in enumerate(cases):
                probe = work / f"contract_{index}.ml"
                probe.write_text(source)
                result = subprocess.run(compiler + [probe.name], cwd=work, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, valid, result.stdout + result.stderr)
                if not valid:
                    self.assertIn("but an expression was expected", result.stderr)


if __name__ == "__main__":
    unittest.main()
