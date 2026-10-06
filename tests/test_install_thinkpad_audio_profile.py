"""Verifica instalación reversible del preset de audio ThinkPad."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/install/install_thinkpad_audio_profile_linux.sh"
DEVICE = "alsa_output.pci-0000_00_1f.3.analog-stereo"


class ThinkPadAudioProfileInstaller(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.data = self.home / ".local/share"
        self.config = self.home / ".config"
        self.state = self.home / ".local/state"
        self._command("dpkg-query", "#!/bin/sh\necho 'install ok installed'\n")
        self._command("easyeffects", "#!/bin/sh\nexit 0\n")
        self._command("sudo", "#!/bin/sh\nexit 0\n")
        self._command("pactl", f'''#!/bin/sh
cat <<'JSON'
[{{"name":"{DEVICE}","ports":[
  {{"name":"analog-output-speaker","description":"Altavoces"}},
  {{"name":"analog-output-headphones","description":"Auriculares"}}
]}}]
JSON
''')
        self.env = os.environ.copy()
        self.env.update({
            "PATH": f"{self.bin}:{self.env.get('PATH', '')}",
            "HOME": str(self.home),
            "XDG_DATA_HOME": str(self.data),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_STATE_HOME": str(self.state),
        })

    def tearDown(self):
        self.temp.cleanup()

    def _command(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

    def _run(self, action):
        return subprocess.run(["bash", str(SCRIPT), action], env=self.env,
                              text=True, capture_output=True, check=False)

    def test_plan_does_not_write_profile_or_autostart(self):
        result = self._run("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("crear autoload para Altavoces y Auriculares", result.stdout)
        self.assertFalse(self.data.exists())
        self.assertFalse(self.config.exists())

    def test_apply_creates_preset_autoload_for_both_ports_and_autostart(self):
        result = self._run("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        preset_path = self.data / "easyeffects/output/ThinkPad X1 Yoga - Voces claras.json"
        preset = json.loads(preset_path.read_text())
        eq = preset["output"]["equalizer#0"]
        self.assertEqual(preset["output"]["plugins_order"], ["equalizer#0"])
        self.assertEqual(eq["input-gain"], -2.0)
        self.assertEqual(eq["left"]["band3"]["gain"], 1.2)
        for route in ("Altavoces", "Auriculares"):
            rule = self.data / f"easyeffects/autoload/output/{DEVICE}:{route}.json"
            self.assertEqual(json.loads(rule.read_text())["preset-name"], "ThinkPad X1 Yoga - Voces claras")
        autostart = self.config / "autostart/com.github.wwmm.easyeffects.desktop"
        self.assertIn("easyeffects --hide-window --service-mode", autostart.read_text())

    def test_rollback_restores_preexisting_autostart_file(self):
        autostart = self.config / "autostart/com.github.wwmm.easyeffects.desktop"
        autostart.parent.mkdir(parents=True)
        autostart.write_text("[Desktop Entry]\nName=Existing\n")
        apply = self._run("--apply")
        self.assertEqual(apply.returncode, 0, apply.stderr)
        rollback = self._run("--rollback")
        self.assertEqual(rollback.returncode, 0, rollback.stderr)
        self.assertEqual(autostart.read_text(), "[Desktop Entry]\nName=Existing\n")
        self.assertFalse((self.data / "easyeffects/output/ThinkPad X1 Yoga - Voces claras.json").exists())


if __name__ == "__main__":
    unittest.main()
