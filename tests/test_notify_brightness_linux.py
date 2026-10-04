"""Prueba los pasos de brillo con brightnessctl simulado, sin tocar hardware."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/hardware/notify_brightness_linux.sh"


class NotifyBrightness(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.state = self.root / "brightness"
        self.notification = self.root / "notification.txt"

        brightnessctl = self.bin / "brightnessctl"
        brightnessctl.write_text(
            """#!/bin/bash
set -euo pipefail
case "$1" in
  get) cat "$MOCK_BRIGHTNESS_STATE" ;;
  max) printf '%s\\n' "$MOCK_BRIGHTNESS_MAX" ;;
  set)
    value="$2"
    current="$(cat "$MOCK_BRIGHTNESS_STATE")"
    if [[ "$value" =~ ^([0-9]+)%$ ]]; then
      target_percent="${BASH_REMATCH[1]}"
      updated=$(((MOCK_BRIGHTNESS_MAX * target_percent + 50) / 100))
    elif [[ "$value" =~ ^\\+([0-9]+)%$ ]]; then
      step="${BASH_REMATCH[1]}"
      delta=$(((MOCK_BRIGHTNESS_MAX * step + 50) / 100))
      updated=$((current + delta))
    elif [[ "$value" =~ ^([0-9]+)%-$ ]]; then
      step="${BASH_REMATCH[1]}"
      delta=$(((MOCK_BRIGHTNESS_MAX * step + 50) / 100))
      updated=$((current - delta))
    else
      exit 2
    fi
    (( updated >= 0 )) || updated=0
    (( updated <= MOCK_BRIGHTNESS_MAX )) || updated="$MOCK_BRIGHTNESS_MAX"
    printf '%s\\n' "$updated" > "$MOCK_BRIGHTNESS_STATE"
    ;;
esac
"""
        )
        brightnessctl.chmod(0o755)
        notify = self.bin / "notify-send"
        notify.write_text(
            """#!/bin/bash
for arg; do last="$arg"; done
printf '%s\\n' "$last" > "$MOCK_NOTIFICATION"
"""
        )
        notify.chmod(0o755)

    def run_helper(self, action, current, maximum=100, **extra_env):
        self.state.write_text(f"{current}\n")
        env = dict(
            os.environ,
            MOCK_BRIGHTNESS_STATE=str(self.state),
            MOCK_BRIGHTNESS_MAX=str(maximum),
            MOCK_NOTIFICATION=str(self.notification),
            PATH=f"{self.bin}:/usr/bin:/bin",
        )
        env.update(extra_env)
        result = subprocess.run(
            ["bash", str(SCRIPT), action], env=env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return int(self.state.read_text()), self.notification.read_text()

    def test_down_uses_one_percent_at_and_below_twenty(self):
        self.assertEqual(self.run_helper("down", 20)[0], 19)
        self.assertEqual(self.run_helper("down", 19)[0], 18)

    def test_up_uses_two_percent_at_and_below_twenty(self):
        self.assertEqual(self.run_helper("up", 20)[0], 22)
        self.assertEqual(self.run_helper("up", 19)[0], 21)

    def test_down_does_not_skip_threshold(self):
        self.assertEqual(self.run_helper("down", 21)[0], 20)

    def test_normal_step_is_preserved_above_threshold(self):
        self.assertEqual(self.run_helper("down", 30)[0], 25)
        self.assertEqual(self.run_helper("up", 30)[0], 35)
        self.assertEqual(self.run_helper("down", 30, BRIGHTNESS_STEP="10")[0], 20)

    def test_changes_saturate_at_zero_and_one_hundred(self):
        self.assertEqual(self.run_helper("down", 0)[0], 0)
        self.assertEqual(self.run_helper("up", 100)[0], 100)

    def test_hardware_resolution_rounds_threshold_and_notification(self):
        actual, notification = self.run_helper("down", 179, maximum=852)
        self.assertEqual(actual, 170)
        self.assertTrue(notification.endswith("20%"), notification)


if __name__ == "__main__":
    unittest.main()
