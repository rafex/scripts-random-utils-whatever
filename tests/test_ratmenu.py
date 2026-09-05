"""Comprueba argumentos del lanzador sin abrir ventanas ni ejecutar acciones."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/system/rafex_ratmenu_linux.sh"


class RatmenuArguments(unittest.TestCase):
    def test_x11_font_and_action_pairs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mock = root / "ratmenu"
            mock.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
            mock.chmod(0o755)
            env = dict(os.environ, HOME=directory, XDG_CONFIG_HOME=directory,
                       PATH=f"{directory}:/usr/bin:/bin")
            result = subprocess.run(["bash", str(SCRIPT)], env=env,
                                    text=True, capture_output=True, check=True)
            args = result.stdout.splitlines()
            self.assertEqual(args[args.index("-font") + 1], "fixed")
            self.assertNotIn("DejaVu Sans Mono-11", args)
            start = args.index("-align") + 2
            self.assertEqual(len(args[start:]) % 2, 0)
            self.assertIn("Panel de control Rafex", args[start:])


if __name__ == "__main__":
    unittest.main()
