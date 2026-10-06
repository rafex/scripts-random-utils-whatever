"""Verifica aplicación y reversión del perfil de micrófono ThinkPad."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/install/install_thinkpad_microphone_profile_linux.sh"
MIC_SOURCE = "alsa_input.pci-0000_00_1f.3.analog-stereo"
MIC_ROUTE = "analog-input-internal-mic"


class ThinkPadMicrophoneProfileInstaller(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.default_source = self.root / "default-source"
        self.default_source.write_text(MIC_SOURCE + "\n")
        self._command("dpkg-query", "#!/bin/sh\necho 'install ok installed'\n")
        self._command("easyeffects", "#!/bin/sh\nexit 0\n")
        self._command("sudo", "#!/bin/sh\nexit 0\n")
        self._command("pactl", f'''#!/bin/sh
case "$1" in
  --format=json)
    [ "$2 $3" = "list sources" ] || exit 2
    cat <<'JSON'
[{{"name":"{MIC_SOURCE}","ports":[{{"name":"{MIC_ROUTE}"}}]}}]
JSON
    ;;
  list)
    [ "$2 $3" = "short sources" ] || exit 2
    printf '42 easyeffects_source PipeWire\\n'
    ;;
  get-default-source)
    cat "$TEST_DEFAULT_SOURCE"
    ;;
  set-default-source)
    printf '%s\\n' "$2" > "$TEST_DEFAULT_SOURCE"
    ;;
  *) exit 2 ;;
esac
''')
        self.env = os.environ.copy()
        self.env.update({
            "PATH": f"{self.bin}:{self.env.get('PATH', '')}",
            "HOME": str(self.home),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_BIN_HOME": str(self.home / ".local/bin"),
            "TEST_DEFAULT_SOURCE": str(self.default_source),
        })

    def tearDown(self):
        self.temp.cleanup()

    def _command(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

    def _run(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                              text=True, capture_output=True, check=False)

    def test_plan_does_not_write_user_configuration(self):
        result = self._run("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("seleccionar easyeffects_source", result.stdout)
        self.assertFalse((self.home / ".local/share").exists())
        self.assertFalse((self.home / ".config").exists())

    def test_apply_creates_input_profile_autostart_and_default_source(self):
        result = self._run("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)

        preset_path = self.home / ".local/share/easyeffects/input/ThinkPad X1 Yoga - Micrófono interno.json"
        preset = json.loads(preset_path.read_text())
        self.assertEqual(preset["input"]["plugins_order"], ["rnnoise#0", "compressor#0", "limiter#0"])
        self.assertFalse(preset["input"]["rnnoise#0"]["bypass"])

        autoload_path = self.home / f".local/share/easyeffects/autoload/input/{MIC_SOURCE}:{MIC_ROUTE}.json"
        autoload = json.loads(autoload_path.read_text())
        self.assertEqual(autoload["device"], MIC_SOURCE)
        self.assertEqual(autoload["device-profile"], MIC_ROUTE)
        self.assertEqual(autoload["preset-name"], "ThinkPad X1 Yoga - Micrófono interno")

        self.assertEqual(self.default_source.read_text().strip(), "easyeffects_source")
        autostart = self.home / ".config/autostart/rafex-easyeffects-microphone.desktop"
        self.assertIn("rafex-easyeffects-mic-start", autostart.read_text())
        self.assertTrue((self.home / ".local/bin/rafex-easyeffects-mic-start").stat().st_mode & 0o111)

    def test_apply_is_repeatable_and_rollback_restores_previous_source(self):
        first = self._run("--apply")
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self._run("--apply")
        self.assertEqual(second.returncode, 0, second.stderr)

        saved_source = self.home / ".local/state/rafex/thinkpad-microphone-profile/default-source"
        self.assertEqual(saved_source.read_text().strip(), MIC_SOURCE)

        rollback = self._run("--rollback")
        self.assertEqual(rollback.returncode, 0, rollback.stderr)
        self.assertEqual(self.default_source.read_text().strip(), MIC_SOURCE)
        self.assertFalse((self.home / ".local/share/easyeffects/input/ThinkPad X1 Yoga - Micrófono interno.json").exists())
        self.assertFalse((self.home / ".config/autostart/rafex-easyeffects-microphone.desktop").exists())


if __name__ == "__main__":
    unittest.main()
