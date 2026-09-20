"""Pruebas privadas del agregador de uso de workspaces de i3."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/system/i3_workspace_usage_linux.py"
SPEC = importlib.util.spec_from_file_location("workspace_usage", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class WorkspaceUsage(unittest.TestCase):
    def test_focused_sample_uses_class_and_instance_not_title(self):
        tree = {"nodes": [{"type": "workspace", "name": "3:web", "focused": True,
                 "nodes": [{"type": "con", "focused": True, "window": 22,
                            "name": "Private browser tab title",
                            "window_properties": {"class": "Firefox", "instance": "Navigator"}}]}]}
        self.assertEqual(MODULE.focused_sample(tree), (3, "firefox", "navigator"))

    def test_report_prefers_focus_time_then_events_and_comments_unknowns(self):
        state = {"version": 1, "entries": [
            {"workspace": 1, "class": "kitty", "instance": "kitty", "focus_seconds": 600, "focus_events": 2, "last_seen": 1},
            {"workspace": 1, "class": "firefox", "instance": "navigator", "focus_seconds": 20, "focus_events": 5, "last_seen": 1},
            {"workspace": 7, "class": "private-app", "instance": "private", "focus_seconds": 600, "focus_events": 8, "last_seen": 1},
        ]}
        draft = MODULE.report(state)
        self.assertIn('set $ws1 "1:term"', draft)
        self.assertIn('assign [class="(?i)^kitty$"] $ws1', draft)
        self.assertIn('# assign [class="(?i)^private-app$"] $ws7', draft)
        self.assertNotIn("Private browser tab title", draft)

    def test_state_round_trip_is_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rafex" / "i3-workspace-usage.json"
            state = {"version": 1, "entries": []}
            MODULE.save_state(path, state)
            self.assertEqual(MODULE.load_state(path), state)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)

    def test_scratchpad_and_non_numeric_workspaces_are_ignored(self):
        scratchpad = {"type": "workspace", "name": "__i3_scratch", "focused": True,
                      "nodes": [{"type": "con", "focused": True, "window": 2,
                                 "window_properties": {"class": "Kitty"}}]}
        self.assertIsNone(MODULE.focused_sample(scratchpad))


if __name__ == "__main__":
    unittest.main()
