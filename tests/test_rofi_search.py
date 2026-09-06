"""Comprueba el dispatcher de rofi_search_linux.sh sin abrir rofi de verdad."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/system/rofi_search_linux.sh"


class RofiSearch(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        self.log = Path(self.temp.name) / "log"
        for name in ("rofi", "pkill", "xdg-open"):
            path = self.mock_bin / name
            path.write_text(f'#!/bin/sh\necho "{name} $*" >> "$LOG"\nexit 0\n')
            path.chmod(0o755)
        self.env = dict(
            os.environ,
            LOG=str(self.log),
            PATH=f"{self.mock_bin}:/usr/bin:/bin",
        )

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                               capture_output=True, text=True)

    def log_lines(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_apps_kills_stale_before_launching(self):
        result = self.run_script("apps")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log_lines()
        self.assertEqual(lines, ["pkill -x rofi", "rofi -show drun -show-icons"])

    def test_default_argument_behaves_like_apps(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log_lines(), ["pkill -x rofi", "rofi -show drun -show-icons"])

    def test_combi_kills_stale_before_launching(self):
        result = self.run_script("combi")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log_lines(), ["pkill -x rofi", "rofi -show combi -show-icons"])

    def test_run_kills_stale_before_launching(self):
        result = self.run_script("run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log_lines(), ["pkill -x rofi", "rofi -show run"])

    def test_browser_does_not_kill_rofi(self):
        result = self.run_script("browser")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log_lines()
        self.assertFalse(any(line.startswith("pkill") for line in lines))
        self.assertTrue(any(line.startswith("xdg-open") for line in lines))

    def test_unknown_argument_prints_usage_and_fails(self):
        result = self.run_script("bogus")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Uso:", result.stderr)
        self.assertEqual(self.log_lines(), [])

    def test_help_prints_usage_without_launching(self):
        result = self.run_script("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Uso:", result.stdout)
        self.assertEqual(self.log_lines(), [])


if __name__ == "__main__":
    unittest.main()
