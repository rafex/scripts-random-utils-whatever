"""Comprueba argumentos del lanzador sin abrir ventanas ni ejecutar acciones."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
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

    @unittest.skipUnless(sys.platform.startswith("linux"), "requiere /proc y flock de Linux")
    def test_second_invocation_is_noop_while_managed_menu_is_open(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mock = root / "ratmenu"
            mock.write_text('#!/bin/sh\ntrap "exit 0" TERM INT\nsleep 10\n')
            mock.chmod(0o755)
            env = dict(os.environ, HOME=directory, XDG_CONFIG_HOME=directory,
                       XDG_RUNTIME_DIR=str(root / "runtime"),
                       PATH=f"{directory}:/usr/bin:/bin")
            first = subprocess.Popen(["bash", str(SCRIPT)], env=env,
                                     text=True, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)
            self.addCleanup(first.terminate)
            time.sleep(0.25)
            second = subprocess.run(["bash", str(SCRIPT)], env=env,
                                    text=True, capture_output=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("no se duplica", second.stdout)
            first.terminate()
            first.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
