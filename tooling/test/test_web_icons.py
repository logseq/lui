"""Web SVG icon constructor contracts on the actual Melange target."""
from pathlib import Path
import subprocess
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WebIcons(unittest.TestCase):
    def test_svg_constructor_types(self):
        subprocess.run(["opam", "exec", "--", "dune", "build", "--profile", "release", "@web"], cwd=ROOT, check=True)
        compiler = ["opam", "exec", "--", "melc"]
        for include in [ROOT / "_build/default/src/.lui.objs/melange",
                        ROOT / "_build/default/platform/web/melange/.lui_web_dom.objs/melange"]:
            compiler.extend(["-I", str(include)])
        valid = """open Lui_web_types
let icon = Icon_svg {svg_view_box = "0 0 24 24"; svg_filled = false;
  svg_shapes = [Svg_path, [Svg_d, "M0 0h1"; Svg_fill, "currentColor"]]}
"""
        cases = [(valid, True),
                 (valid.replace("Svg_path", "Svg_script"), False),
                 (valid.replace("Svg_d,", "Svg_onload,"), False),
                 ('let _ = Lui_web_types.Icon_svg "<svg/>"', False)]
        with tempfile.TemporaryDirectory(prefix="lui-web-icon-types-") as temporary:
            for index, (source, accepted) in enumerate(cases):
                path = Path(temporary) / f"icon_{index}.ml"
                path.write_text(source)
                result = subprocess.run(compiler + [path.name], cwd=temporary, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)
                if not accepted:
                    self.assertIn("Error:", re.sub(r"\x1b\[[0-9;]*m", "", result.stderr))


if __name__ == "__main__":
    unittest.main()
