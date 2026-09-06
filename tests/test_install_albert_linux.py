"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

Requiere Debian real (el script exige /etc/os-release ID=debian) -- se
valida en el ThinkPad, igual que test_reconcile_runtimes.py.
sudo/apt-get/apt-cache/install/wget se mockean para no tocar el sistema
real ni requerir contraseña.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install/install_albert_linux.sh"
FIXTURE_KEY = Path(__file__).resolve().parent / "fixtures/albert_release_key.dat"

SUDO_MOCK = '#!/bin/sh\ncase "$1" in\n  -v) exit 0 ;;\nesac\nexec "$@"\n'

LOGGING_NOOP_MOCK = '#!/bin/sh\necho "{name} $*" >> "$LOG"\nexit 0\n'

WGET_MOCK = '''#!/bin/sh
dest=""
for arg in "$@"; do
  case "$arg" in
    --output-document=*) dest="${arg#--output-document=}" ;;
  esac
done
echo "wget $*" >> "$LOG"
case "$*" in
  *Release.key*) cp "$FIXTURE_KEY" "$dest"; exit 0 ;;
esac
exit 1
'''


class InstallAlbertLinux(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        self.log = Path(self.temp.name) / "log"
        self.write(self.mock_bin / "sudo", SUDO_MOCK)
        for name in ("apt-get", "apt-cache", "install"):
            self.write(self.mock_bin / name, LOGGING_NOOP_MOCK.format(name=name))
        self.write(self.mock_bin / "wget", WGET_MOCK)
        self.env = dict(
            os.environ,
            LOG=str(self.log),
            FIXTURE_KEY=str(FIXTURE_KEY),
            PATH=f"{self.mock_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
        )

    def write(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                               capture_output=True, text=True)

    def log_lines(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_help_does_not_require_debian(self):
        result = self.run_script("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install_albert_linux.sh", result.stdout)

    def test_unknown_argument_is_rejected(self):
        result = self.run_script("--bogus")
        self.assertNotEqual(result.returncode, 0)

    def test_check_makes_no_mutating_calls(self):
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = self.log_lines()
        self.assertFalse(any("install " in line for line in lines))
        self.assertFalse(any(line.startswith("apt-get install") for line in lines))

    def test_plan_makes_no_mutating_calls_and_announces_install(self):
        result = self.run_script("--plan")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("apt-get install -y albert", result.stdout)
        self.assertEqual(self.log_lines(), [])

    def test_plan_with_i3_shortcut_announces_bindsym(self):
        result = self.run_script("--plan", "--i3-shortcut")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("mod+a", result.stdout)
        self.assertEqual(self.log_lines(), [])

    def test_apply_downloads_and_verifies_real_key_then_installs(self):
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = self.log_lines()
        self.assertTrue(any("Release.key" in line for line in lines))
        self.assertTrue(any(line == "apt-get install -y albert" for line in lines),
                         lines)

    def test_apply_rejects_key_with_wrong_checksum(self):
        mutated = Path(self.temp.name) / "mutated.key"
        original = FIXTURE_KEY.read_bytes()
        mutated.write_bytes(bytes([original[0] ^ 0xFF]) + original[1:])
        env = dict(self.env, FIXTURE_KEY=str(mutated))
        result = subprocess.run(["bash", str(SCRIPT), "--apply"], env=env,
                                 capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum SHA256 inesperado", result.stderr)
        lines = self.log.read_text().splitlines() if self.log.exists() else []
        self.assertFalse(any(line == "apt-get install -y albert" for line in lines))

    def test_apply_with_i3_shortcut_patches_deployed_i3_config(self):
        i3_dir = Path(self.temp.name) / "config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\nbindsym $mod+Return exec alacritty\n")
        env = dict(self.env, XDG_CONFIG_HOME=str(Path(self.temp.name) / "config"))
        result = subprocess.run(["bash", str(SCRIPT), "--apply", "--i3-shortcut"],
                                 env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        content = i3_config.read_text()
        self.assertIn("# BEGIN rafex albert", content)
        self.assertIn("bindsym $mod+a exec --no-startup-id albert show", content)
        self.assertIn("# END rafex albert", content)
        self.assertIn("bindsym $mod+Return exec alacritty", content)

    def test_apply_i3_shortcut_is_idempotent(self):
        i3_dir = Path(self.temp.name) / "config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\n")
        env = dict(self.env, XDG_CONFIG_HOME=str(Path(self.temp.name) / "config"))
        subprocess.run(["bash", str(SCRIPT), "--apply", "--i3-shortcut"],
                        env=env, capture_output=True, text=True, check=True)
        first_content = i3_config.read_text()
        result = subprocess.run(["bash", str(SCRIPT), "--apply", "--i3-shortcut"],
                                 env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(i3_config.read_text(), first_content)
        backups = list(i3_dir.glob("config.bak.*"))
        self.assertEqual(len(backups), 1, "solo el primer parchado debe generar respaldo")


if __name__ == "__main__":
    unittest.main()
