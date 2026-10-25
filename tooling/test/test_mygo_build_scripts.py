"""Exercise Linux shared-library scripts without a preexisting Dune cache."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MyGoBuildScriptsTest(unittest.TestCase):
    def test_linux_builds_every_linked_archive_from_empty_build_directory(self):
        for application in ("todos", "components"):
            with self.subTest(application=application), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tools = root / "bin"
                tools.mkdir()
                (root / "tooling").mkdir()
                script = root / "tooling" / f"build_mygo_{application}.sh"
                shutil.copyfile(ROOT / "tooling" / script.name, script)
                commands = {
                    "uname": "#!/bin/sh\nprintf 'Linux\\n'\n",
                    "opam": '''#!/usr/bin/env python3
from pathlib import Path
import sys
args = sys.argv[1:]
assert args[:2] == ["exec", "--"], args
args = args[2:]
if args[:2] == ["dune", "build"]:
    for target in args[2:]:
        path = Path("_build/default") / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
elif args[:2] == ["ocamlfind", "ocamlopt"]:
    for target in args:
        if target.endswith(".cmxa") and not Path(target).is_file():
            sys.exit("Archive missing from fresh Dune build: " + target)
    Path(args[args.index("-o") + 1]).touch()
elif args == ["ocamlc", "-where"]:
    print("/ocaml/include")
else:
    sys.exit("Unexpected command: " + str(args))
''',
                    "cc": '''#!/usr/bin/env python3
from pathlib import Path
import sys
Path(sys.argv[sys.argv.index("-o") + 1]).touch()
''',
                }
                for name, body in commands.items():
                    path = tools / name
                    path.write_text(body)
                    path.chmod(0o755)
                result = subprocess.run(
                    ["bash", str(script)], env={**os.environ, "PATH": f"{tools}:{os.environ['PATH']}"},
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(Path(result.stdout.strip()), root / "_build/mygo" / f"liblui_{application}.so")
                self.assertTrue(Path(result.stdout.strip()).exists())


if __name__ == "__main__":
    unittest.main()
