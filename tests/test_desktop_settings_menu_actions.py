"""Prueba el registro de acciones de energía sin ejecutarlas en el equipo."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/system/desktop_settings_menu_linux.sh"


class DesktopSettingsActions(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.state = self.root / "state"
        self.calls = self.root / "calls.log"
        self.notification = self.root / "notification.txt"
        self.write_command(
            "rofi",
            'cat >/dev/null\nprintf "%s\\n" "${MOCK_ROFI_CHOICE:-Confirmar}"\n',
        )
        self.write_command(
            "notify-send",
            'printf "%s\\n" "$@" > "$MOCK_NOTIFICATION"\n',
        )
        self.write_command(
            "loginctl",
            """printf '%s\\n' "$*" >> "$MOCK_CALLS"
case "$1" in
  can-hibernate) printf '%s\\n' "${MOCK_HIBERNATE_CAPABILITY:-yes}"; exit "${MOCK_HIBERNATE_QUERY_EXIT:-0}" ;;
  suspend|hibernate) printf '%s\\n' "${MOCK_ACTION_OUTPUT:-}" >&2; exit "${MOCK_ACTION_EXIT:-0}" ;;
  show-session) printf 'Active=yes\\nState=active\\nType=x11\\n'; exit 0 ;;
  terminate-session) printf '%s\\n' "${MOCK_ACTION_OUTPUT:-}" >&2; exit "${MOCK_ACTION_EXIT:-0}" ;;
esac
exit 0
""",
        )
        self.write_command(
            "systemctl",
            'printf "%s\\n" "$*" >> "$MOCK_CALLS"\nprintf "%s\\n" "${MOCK_ACTION_OUTPUT:-}" >&2\nexit "${MOCK_ACTION_EXIT:-0}"\n',
        )
        self.write_command(
            "busctl",
            'case "$*" in *CanSuspend*) echo \'s "yes"\' ;; *) echo \'s "challenge"\' ;; esac\n',
        )
        self.write_command("systemd-inhibit", "echo 'No inhibitors.'\n")

    def write_command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def run_helper(self, action, **extra_env):
        env = dict(
            os.environ,
            HOME=str(self.root),
            XDG_STATE_HOME=str(self.state),
            XDG_SESSION_ID="test-session",
            RAFEX_ACTION_SOURCE="ratmenu",
            MOCK_CALLS=str(self.calls),
            MOCK_NOTIFICATION=str(self.notification),
            PATH=f"{self.bin}:/usr/bin:/bin",
        )
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(SCRIPT), action], env=env, text=True, capture_output=True
        )

    def records(self):
        log = self.state / "rafex/ratmenu-actions.jsonl"
        return log, [json.loads(line) for line in log.read_text().splitlines()]

    def test_suspend_failure_shows_error_and_logs_diagnostics(self):
        result = self.run_helper(
            "suspend", MOCK_ACTION_EXIT="1", MOCK_ACTION_OUTPUT="Access denied"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        notification = self.notification.read_text()
        self.assertIn("Access denied", notification)
        self.assertIn("código 1", notification)

        log, records = self.records()
        self.assertEqual(len(records), 1)
        event = records[0]
        self.assertEqual(event["source"], "ratmenu")
        self.assertEqual(event["action"], "suspend")
        self.assertEqual(event["result"], "failure")
        self.assertEqual(event["exit_code"], 1)
        self.assertEqual(event["output"].strip(), "Access denied")
        self.assertEqual(event["command"], ["loginctl", "suspend"])
        self.assertIn('CanSuspend: s "yes"', event["diagnostics"])
        self.assertIn("Inhibitors:", event["diagnostics"])
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)
        self.assertEqual(log.parent.stat().st_mode & 0o777, 0o700)

    def test_cancelled_suspend_is_logged_without_calling_loginctl(self):
        result = self.run_helper("suspend", MOCK_ROFI_CHOICE="Cancelar")
        self.assertEqual(result.returncode, 0, result.stderr)
        log, records = self.records()
        self.assertEqual(records[0]["result"], "cancelled")
        self.assertIsNone(records[0]["exit_code"])
        self.assertFalse(self.calls.exists())
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)

    def test_successful_poweroff_is_logged(self):
        result = self.run_helper("poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        _, records = self.records()
        self.assertEqual(records[0]["action"], "poweroff")
        self.assertEqual(records[0]["result"], "success")
        self.assertEqual(records[0]["exit_code"], 0)
        self.assertEqual(records[0]["command"], ["systemctl", "poweroff"])

    def test_unavailable_hibernate_capability_is_logged(self):
        result = self.run_helper("hibernate", MOCK_HIBERNATE_CAPABILITY="no")
        self.assertEqual(result.returncode, 0, result.stderr)
        _, records = self.records()
        self.assertEqual(records[0]["action"], "hibernate")
        self.assertEqual(records[0]["result"], "unavailable")
        self.assertEqual(records[0]["output"].strip(), "no")
        self.assertEqual(records[0]["command"], ["loginctl", "can-hibernate"])
        self.assertEqual(self.calls.read_text().splitlines(), ["can-hibernate"])


if __name__ == "__main__":
    unittest.main()
