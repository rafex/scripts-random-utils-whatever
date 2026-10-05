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
        self.xrandr_state = self.root / "xrandr-brightness"
        self.xdg_state = self.root / "xdg-state"
        self.xdg_state.mkdir()
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

        xrandr = self.bin / "xrandr"
        xrandr.write_text(
            """#!/bin/bash
set -euo pipefail
case "$1" in
  --query)
    [[ "${MOCK_XRANDR_FAIL_QUERY:-0}" != 1 ]] || exit 1
    printf 'eDP-1 connected primary 1920x1080+0+0\\n'
    ;;
  --verbose)
    printf 'eDP-1 connected primary 1920x1080+0+0\\n'
    value="$(cat "$MOCK_XRANDR_STATE")"
    rounded="$(awk -v value="$value" 'BEGIN { printf "%.1f", int(value * 10 + 0.500001) / 10 }')"
    printf '    Brightness: %s\\n' "$rounded"
    ;;
  --output)
    [[ "$2" == eDP-1 && "$3" == --brightness ]] || exit 2
    printf '%s\\n' "$4" > "$MOCK_XRANDR_STATE"
    ;;
  *) exit 2 ;;
esac
"""
        )
        xrandr.chmod(0o755)

    def run_helper(self, action, current, maximum=100, **extra_env):
        self.state.write_text(f"{current}\n")
        self.xrandr_state.write_text(extra_env.pop("MOCK_XRANDR_INITIAL", "1.10") + "\n")
        env = dict(
            os.environ,
            MOCK_BRIGHTNESS_STATE=str(self.state),
            MOCK_BRIGHTNESS_MAX=str(maximum),
            MOCK_NOTIFICATION=str(self.notification),
            MOCK_XRANDR_STATE=str(self.xrandr_state),
            XDG_STATE_HOME=str(self.xdg_state),
            PATH=f"{self.bin}:/usr/bin:/bin",
        )
        env.update(extra_env)
        result = subprocess.run(
            ["bash", str(SCRIPT), action], env=env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return int(self.state.read_text()), self.notification.read_text()

    def run_helper_with_xrandr(self, action, xrandr_initial, current=100):
        self.state.write_text(f"{current}\n")
        self.xrandr_state.write_text(f"{xrandr_initial}\n")
        state_file = self.xdg_state / "brightness-notify" / "eDP-1.level"
        state_file.parent.mkdir(exist_ok=True)
        state_file.write_text(f"{xrandr_initial}\n")
        env = dict(
            os.environ,
            MOCK_BRIGHTNESS_STATE=str(self.state),
            MOCK_BRIGHTNESS_MAX="100",
            MOCK_NOTIFICATION=str(self.notification),
            MOCK_XRANDR_STATE=str(self.xrandr_state),
            XDG_STATE_HOME=str(self.xdg_state),
            PATH=f"{self.bin}:/usr/bin:/bin",
        )
        result = subprocess.run(
            ["bash", str(SCRIPT), action], env=env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return int(self.state.read_text()), self.xrandr_state.read_text().strip(), self.notification.read_text()

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

    def test_xrandr_extends_brightness_over_one_hundred(self):
        hardware, software, notification = self.run_helper_with_xrandr("up", "1.10")
        self.assertEqual((hardware, software), (100, "1.15"))
        self.assertIn("xrandr 1.15", notification)

    def test_xrandr_is_reduced_before_hardware_brightness(self):
        hardware, software, _ = self.run_helper_with_xrandr("down", "1.15")
        self.assertEqual((hardware, software), (100, "1.10"))

    def test_xrandr_caps_at_two(self):
        _, software, _ = self.run_helper_with_xrandr("up", "1.99")
        self.assertEqual(software, "2.00")
        _, software, _ = self.run_helper_with_xrandr("up", "2.00")
        self.assertEqual(software, "2.00")

    def test_hardware_decreases_after_xrandr_returns_to_base(self):
        hardware, software, _ = self.run_helper_with_xrandr("down", "1.10")
        self.assertEqual((hardware, software), (95, "1.10"))

    def test_repeated_xrandr_decrements_keep_sub_tenth_precision(self):
        self.run_helper_with_xrandr("down", "1.70")
        self.assertEqual(self.xrandr_state.read_text().strip(), "1.65")

        env = dict(
            os.environ,
            MOCK_BRIGHTNESS_STATE=str(self.state),
            MOCK_BRIGHTNESS_MAX="100",
            MOCK_NOTIFICATION=str(self.notification),
            MOCK_XRANDR_STATE=str(self.xrandr_state),
            XDG_STATE_HOME=str(self.xdg_state),
            PATH=f"{self.bin}:/usr/bin:/bin",
        )
        result = subprocess.run(
            ["bash", str(SCRIPT), "down"], env=env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.xrandr_state.read_text().strip(), "1.60")

    def test_xrandr_failure_reports_display_diagnostic(self):
        self.state.write_text("100\n")
        env = dict(
            os.environ,
            MOCK_BRIGHTNESS_STATE=str(self.state),
            MOCK_BRIGHTNESS_MAX="100",
            MOCK_NOTIFICATION=str(self.notification),
            MOCK_XRANDR_STATE=str(self.xrandr_state),
            MOCK_XRANDR_FAIL_QUERY="1",
            PATH=f"{self.bin}:/usr/bin:/bin",
        )
        result = subprocess.run(
            ["bash", str(SCRIPT), "up"], env=env, text=True, capture_output=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DISPLAY=", result.stderr)

    def test_hardware_resolution_rounds_threshold_and_notification(self):
        actual, notification = self.run_helper("down", 179, maximum=852)
        self.assertEqual(actual, 170)
        self.assertTrue(notification.endswith("20%"), notification)


if __name__ == "__main__":
    unittest.main()
