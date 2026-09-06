"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

GRUB_FILE es una ruta absoluta de sistema sin override posible -igual que
otros instaladores de este repo (harden_thinkpad_linux.sh)-, así que
--apply de verdad (escritura + sudo update-grub) se valida en vivo en el
ThinkPad, no aquí. `uname` se mockea para poder ejercitar la lógica en
cualquier plataforma.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/hardware/configure_thinkpad_mem_sleep_linux.sh"

UNAME_MOCK = '#!/bin/sh\n[ "$1" = "-s" ] && echo Linux || echo unknown\n'


class ConfigureThinkpadMemSleep(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        (self.mock_bin / "uname").write_text(UNAME_MOCK)
        (self.mock_bin / "uname").chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=f"{self.mock_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
        )

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                               capture_output=True, text=True)

    def test_help_does_not_require_linux(self):
        result = subprocess.run(["bash", str(SCRIPT), "--help"], env=dict(os.environ),
                                 capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("configure_thinkpad_mem_sleep_linux.sh", result.stdout)
        self.assertIn("s2idle|deep", result.stdout)

    def test_defaults_to_s2idle(self):
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("objetivo: s2idle", result.stdout)

    def test_rejects_unsupported_mode(self):
        result = self.run_script("--check", "--mode", "shallow")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("modo no soportado", result.stderr)

    def test_accepts_deep_mode(self):
        result = self.run_script("--check", "--mode", "deep")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("objetivo: deep", result.stdout)

    def test_plan_mentions_requested_mode_and_makes_no_mutating_calls(self):
        result = self.run_script("--plan", "--mode", "deep")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("mem_sleep_default=deep", result.stdout)
        self.assertIn("no se reiniciará automáticamente", result.stdout + result.stderr)

    def test_mode_requires_a_value(self):
        result = self.run_script("--check", "--mode")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--mode requiere un valor", result.stderr)


if __name__ == "__main__":
    unittest.main()
