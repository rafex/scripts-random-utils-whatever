"""Pruebas sin red ni cambios en instalaciones reales: python3 -m unittest discover -s tests."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/dev/find_safety_backups_unix.sh"


class FindSafetyBackups(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / ".config"
        self.config.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home))

    def plant(self, relpath, content="hi\n"):
        path = self.home / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def run_script(self, *args, input_text=None):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                               capture_output=True, text=True, input=input_text)

    def test_finds_underscore_format(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000")
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(backup), result.stdout)

    def test_finds_underscore_format_with_collision_suffix(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000.1")
        result = self.run_script("--check")
        self.assertIn(str(backup), result.stdout)

    def test_finds_dash_mktemp_format(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak-20260101-120000.Ab3dE9")
        result = self.run_script("--check")
        self.assertIn(str(backup), result.stdout)

    def test_ignores_unrelated_bak_like_names(self):
        self.plant(".config/foo.conf")
        notes = self.plant(".config/notes.bak.txt")
        oldish = self.plant(".config/notes.bak-old")
        plain = self.plant(".config/plain.conf")
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in (notes, oldish, plain):
            self.assertNotIn(str(path), result.stdout)

    def test_prunes_excluded_subtrees(self):
        self.plant(".config/foo.conf")
        cached = self.plant(".cache/x.bak.20260101_120000")
        dedicated = self.plant(".local/state/rafex/backups/x.bak.20260101_120000")
        result = self.run_script("--check")
        self.assertNotIn(str(cached), result.stdout)
        self.assertNotIn(str(dedicated), result.stdout)

    def test_home_dotfile_found_but_nested_project_dir_not_recursed(self):
        # $HOME propio se escanea solo a profundidad 1 (dotfiles directos
        # como .bashrc.bak.<fecha>), nunca dentro de árboles de proyecto
        # arbitrarios que el usuario tenga en su home (evita que el
        # escaneo se vaya por directorios enormes ajenos al repo).
        direct = self.plant(".bashrc.bak.20260101_120000")
        nested = self.plant("some-project/deep/dir/file.conf.bak.20260101_120000")
        result = self.run_script("--check")
        self.assertIn(str(direct), result.stdout)
        self.assertNotIn(str(nested), result.stdout)

    def test_check_makes_zero_changes(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000")
        before = backup.read_bytes()
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(backup.exists())
        self.assertEqual(backup.read_bytes(), before)

    def test_plan_makes_zero_changes_and_mentions_plan(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000")
        result = self.run_script("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(backup.exists())
        self.assertIn("[plan]", result.stdout)

    def test_apply_all_deletes_everything_found(self):
        self.plant(".config/foo.conf")
        b1 = self.plant(".config/foo.conf.bak.20260101_120000")
        b2 = self.plant(".config/foo.conf.bak.20260102_120000")
        original = self.home / ".config/foo.conf"
        result = self.run_script("--apply", "--all")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(b1.exists())
        self.assertFalse(b2.exists())
        self.assertTrue(original.exists())

    def test_all_without_apply_is_rejected(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000")
        result = self.run_script("--all")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(backup.exists())

    def test_interactive_picker_deletes_selected_index(self):
        self.plant(".config/foo.conf")
        b1 = self.plant(".config/foo.conf.bak.20260101_120000")
        b2 = self.plant(".config/foo.conf.bak.20260102_120000")
        result = self.run_script("--apply", input_text="1\ny\nq\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # El índice 1 corresponde al primer hallazgo listado; solo uno de
        # los dos debe sobrevivir.
        survivors = [p.exists() for p in (b1, b2)]
        self.assertEqual(survivors.count(True), 1)

    def test_interactive_picker_all_token(self):
        self.plant(".config/foo.conf")
        b1 = self.plant(".config/foo.conf.bak.20260101_120000")
        b2 = self.plant(".config/foo.conf.bak.20260102_120000")
        result = self.run_script("--apply", input_text="todo\ny\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(b1.exists())
        self.assertFalse(b2.exists())

    def test_interactive_picker_range_and_comma_list(self):
        self.plant(".config/foo.conf")
        backups = [self.plant(f".config/foo.conf.bak.2026010{i}_120000") for i in range(1, 5)]
        result = self.run_script("--apply", input_text="1,3\ny\nq\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        survivors = sum(p.exists() for p in backups)
        self.assertEqual(survivors, 2)

    def test_interactive_picker_confirm_declines(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000")
        result = self.run_script("--apply", input_text="1\nn\nq\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(backup.exists())

    def test_interactive_picker_quits_immediately(self):
        self.plant(".config/foo.conf")
        backup = self.plant(".config/foo.conf.bak.20260101_120000")
        result = self.run_script("--apply", input_text="q\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(backup.exists())

    def test_original_missing_is_still_deletable(self):
        backup = self.plant(".config/gone.conf.bak.20260101_120000")
        result = self.run_script("--apply", "--all")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(backup.exists())

    def test_backup_directory_is_treated_as_one_finding(self):
        # install_terminal_workstation_linux.sh respalda directorios enteros
        # con el mismo sufijo (p. ej. ~/.config/nvim.bak.<fecha>/).
        backup_dir = self.plant(".config/nvim.bak.20260101_120000/init.vim").parent
        result = self.run_script("--check")
        self.assertEqual(result.stdout.count(str(backup_dir)), 1)
        apply_result = self.run_script("--apply", "--all")
        self.assertEqual(apply_result.returncode, 0, apply_result.stderr)
        self.assertFalse(backup_dir.exists())


if __name__ == "__main__":
    unittest.main()
