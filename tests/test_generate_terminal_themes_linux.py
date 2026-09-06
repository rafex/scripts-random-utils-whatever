"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

SOURCE_ROOT siempre apunta a las plantillas reales del repo (se deriva de la
ubicación del propio script, sin override), así que estas pruebas solo
aíslan el destino (XDG_CONFIG_HOME) y comparan contra el contenido real de
dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/themes/. `uname` se
mockea para poder ejercitar la lógica en cualquier plataforma.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/system/generate_terminal_themes_linux.sh"
SOURCE_ROOT = REPO_ROOT / "dotfiles/profiles/thinkpad-x1-yoga-1st/config/rafex/themes"

UNAME_MOCK = '#!/bin/sh\n[ "$1" = "-s" ] && echo Linux || echo unknown\n'


class GenerateTerminalThemes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config_home = Path(self.temp.name) / "config"
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        (self.mock_bin / "uname").write_text(UNAME_MOCK)
        (self.mock_bin / "uname").chmod(0o755)
        self.env = dict(
            os.environ,
            XDG_CONFIG_HOME=str(self.config_home),
            PATH=f"{self.mock_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
        )

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                               capture_output=True, text=True)

    def target_file(self, theme, name):
        return self.config_home / "rafex/themes" / theme / name

    def test_check_reports_missing_when_never_applied(self):
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nord=missing", result.stdout)
        self.assertIn("paper=missing", result.stdout)

    def test_apply_then_check_is_up_to_date(self):
        apply_result = self.run_script("--apply", "--theme", "nord")
        self.assertEqual(apply_result.returncode, 0, apply_result.stderr)
        check_result = self.run_script("--check")
        self.assertIn("nord=up-to-date", check_result.stdout)

    def test_apply_is_idempotent_no_op_on_second_run(self):
        self.run_script("--apply", "--theme", "nord")
        alacritty = self.target_file("nord", "alacritty.toml")
        before = alacritty.read_bytes()
        before_mtime = alacritty.stat().st_mtime_ns
        result = self.run_script("--apply", "--theme", "nord")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(alacritty.read_bytes(), before)
        self.assertEqual(alacritty.stat().st_mtime_ns, before_mtime)

    def test_stale_file_is_detected_and_makes_zero_changes_on_check(self):
        self.run_script("--apply", "--theme", "nord")
        alacritty = self.target_file("nord", "alacritty.toml")
        alacritty.write_text("background = \"#ffffff\"\n")
        check_result = self.run_script("--check")
        self.assertIn("nord=stale", check_result.stdout)
        # --check nunca debe modificar el archivo detectado como obsoleto.
        self.assertEqual(alacritty.read_text(), "background = \"#ffffff\"\n")

    def test_plan_lists_the_specific_stale_file(self):
        self.run_script("--apply", "--theme", "nord")
        alacritty = self.target_file("nord", "alacritty.toml")
        alacritty.write_text("background = \"#ffffff\"\n")
        plan_result = self.run_script("--plan", "--theme", "nord")
        self.assertEqual(plan_result.returncode, 0, plan_result.stderr)
        self.assertIn("alacritty.toml (desactualizado)", plan_result.stdout)
        self.assertNotIn("tmux.conf (desactualizado)", plan_result.stdout)

    def test_incomplete_when_a_file_is_missing(self):
        self.run_script("--apply", "--theme", "nord")
        self.target_file("nord", "eww.scss").unlink()
        result = self.run_script("--check")
        self.assertIn("nord=incomplete", result.stdout)

    def test_plan_makes_zero_changes(self):
        self.run_script("--apply", "--theme", "nord")
        alacritty = self.target_file("nord", "alacritty.toml")
        before = alacritty.read_bytes()
        result = self.run_script("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(alacritty.read_bytes(), before)

    def test_apply_fixes_a_stale_file(self):
        self.run_script("--apply", "--theme", "nord")
        alacritty = self.target_file("nord", "alacritty.toml")
        alacritty.write_text("background = \"#ffffff\"\n")
        self.run_script("--apply", "--theme", "nord")
        self.assertEqual(
            alacritty.read_bytes(),
            (SOURCE_ROOT / "nord/alacritty.toml").read_bytes(),
        )


if __name__ == "__main__":
    unittest.main()
