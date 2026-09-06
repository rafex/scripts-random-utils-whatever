"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

El script exige Linux real (`uname -s`); se mockea `uname` en PATH para
poder ejercitar la lógica en cualquier plataforma. El hook de
systemd-sleep vive en una ruta absoluta de sistema
(/lib/systemd/system-sleep/...) sin override posible -igual que otros
instaladores de este repo (harden_thinkpad_linux.sh, install_albert_linux.sh)-,
así que --apply de verdad se valida en vivo en el ThinkPad, no aquí; estas
pruebas cubren --check/--plan y el parchado idempotente de i3 (que sí
respeta XDG_CONFIG_HOME).
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/hardware/configure_xrandr_brightness_linux.sh"

UNAME_MOCK = '#!/bin/sh\n[ "$1" = "-s" ] && echo Linux || echo unknown\n'

XRANDR_MOCK = '''#!/bin/sh
case "$1" in
  --query)
    echo "Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767"
    echo "eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 277mm x 156mm"
    ;;
  --verbose)
    echo "eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 277mm x 156mm"
    echo "	Identifier: 0x123"
    echo "	Brightness: 1.0"
    ;;
  --output) exit 0 ;;
esac
exit 0
'''

LOGGING_NOOP_MOCK = '#!/bin/sh\necho "{name} $*" >> "$LOG"\nexit 0\n'
SUDO_MOCK = '#!/bin/sh\ncase "$1" in\n  -v) exit 0 ;;\n  -n) shift; exec "$@" ;;\nesac\nexec "$@"\n'


class ConfigureXrandrBrightness(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        self.log = Path(self.temp.name) / "log"
        self.write(self.mock_bin / "uname", UNAME_MOCK)
        self.write(self.mock_bin / "xrandr", XRANDR_MOCK)
        self.write(self.mock_bin / "sudo", SUDO_MOCK)
        for name in ("install", "su"):
            self.write(self.mock_bin / name, LOGGING_NOOP_MOCK.format(name=name))
        self.env = dict(
            os.environ,
            LOG=str(self.log),
            DISPLAY=":0",
            PATH=f"{self.mock_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
        )

    def write(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, *args, env=None):
        return subprocess.run(["bash", str(SCRIPT), *args], env=env or self.env,
                               capture_output=True, text=True)

    def log_lines(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_help_does_not_require_linux(self):
        env = dict(os.environ)
        result = subprocess.run(["bash", str(SCRIPT), "--help"], env=env,
                                 capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("configure_xrandr_brightness_linux.sh", result.stdout)

    def test_rejects_non_numeric_brightness(self):
        result = self.run_script("--check", "--brightness", "abc")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inválido", result.stderr)

    def test_rejects_out_of_range_brightness(self):
        result = self.run_script("--check", "--brightness", "5.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fuera de rango", result.stderr)

    def test_check_detects_output_and_current_brightness(self):
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("salida detectada: eDP-1", result.stdout)
        self.assertIn("brillo actual=1.0", result.stdout)
        self.assertEqual(self.log_lines(), [])

    def test_plan_makes_no_mutating_calls(self):
        result = self.run_script("--plan", "--brightness", "1.2")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("brillo: 1.2", result.stdout)
        self.assertEqual(self.log_lines(), [])

    def test_apply_patches_i3_config_idempotently(self):
        i3_dir = Path(self.temp.name) / "config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\nbindsym $mod+Return exec alacritty\n")
        env = dict(self.env, XDG_CONFIG_HOME=str(Path(self.temp.name) / "config"))

        result = subprocess.run(["bash", str(SCRIPT), "--apply", "--brightness", "1.15"],
                                 env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        content = i3_config.read_text()
        self.assertIn("# BEGIN rafex xrandr-brightness", content)
        self.assertIn("exec_always --no-startup-id xrandr --output eDP-1 --brightness 1.15", content)
        self.assertIn("# END rafex xrandr-brightness", content)
        self.assertIn("bindsym $mod+Return exec alacritty", content)

        first_content = content
        result2 = subprocess.run(["bash", str(SCRIPT), "--apply", "--brightness", "1.15"],
                                  env=env, capture_output=True, text=True)
        self.assertEqual(result2.returncode, 0, result2.stdout + result2.stderr)
        self.assertEqual(i3_config.read_text(), first_content)
        backups = list(i3_dir.glob("config.bak.*"))
        self.assertEqual(len(backups), 1, "solo el primer parchado debe generar respaldo")

    def test_no_output_detected_without_display(self):
        env = dict(self.env)
        env.pop("DISPLAY", None)
        result = subprocess.run(["bash", str(SCRIPT), "--check"], env=env,
                                 capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no se detectó una salida interna", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
