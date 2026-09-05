"""Pruebas sin red ni cambios en instalaciones reales: python3 -m unittest discover -s tests."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/dev/update_opencode_unix.sh"


@unittest.skipIf(os.geteuid() == 0, "El actualizador rechaza root")
class UpdateOpenCode(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.original = self.home / ".opencode/bin/opencode"
        self.active = self.home / ".local/bin/opencode"
        self.mock = self.home / "mock"
        self.mock.mkdir()
        for path in (self.original, self.active):
            self.executable(path, '#!/bin/sh\nprintf "1.0.0\\n"\n')
        self.executable(self.mock / "curl", '''#!/bin/bash
while (( $# )); do
  if [[ "$1" == -o ]]; then cp "$HOME/installer" "$2"; exit; fi
  shift
done
exit 1
''')
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{self.mock}:{self.active.parent}:/usr/bin:/bin:/usr/sbin:/sbin")

    def executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                              capture_output=True, text=True)

    def installer(self, fail=False):
        self.executable(self.home / "installer", '''#!/bin/bash
[[ "$1" == --no-modify-path ]] || exit 2
[[ -z "${VERSION:-}" ]] || exit 3
printf '#!/bin/sh\\nprintf "2.0.0\\\\n"\\n' > "$HOME/.opencode/bin/opencode"
chmod 755 "$HOME/.opencode/bin/opencode"
''' + ("exit 1\n" if fail else "exit 0\n"))

    def test_read_only_actions(self):
        before = self.original.read_bytes()
        for action in ("--check", "--plan", "--status"):
            result = self.run_script(action)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.original.read_bytes(), before)
        self.assertEqual(list((self.home / ".opencode").iterdir()), [self.original.parent])

    def test_apply_sync_and_environment(self):
        self.installer()
        self.env["VERSION"] = "unexpected"
        result = self.run_script("--apply", "--version", "2.0.0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.original.read_bytes(), self.active.read_bytes())
        backups = list((self.home / ".opencode").glob("rafex-update-*"))
        self.assertEqual(len(backups), 1)
        self.assertIn("1.0.0", (backups[0] / "active").read_text())

    def test_failure_restores(self):
        self.installer(fail=True)
        before = self.original.read_bytes()
        self.assertNotEqual(self.run_script("--apply").returncode, 0)
        self.assertEqual(self.original.read_bytes(), before)
        self.assertEqual(self.active.read_bytes(), before)
        self.assertFalse((self.home / ".opencode/.rafex-update.lock").exists())

    def test_version_mismatch_restores(self):
        self.installer()
        before = self.original.read_bytes()
        self.assertNotEqual(self.run_script("--apply", "--version", "3.0.0").returncode, 0)
        self.assertEqual(self.original.read_bytes(), before)

    def test_rejects_symlink_and_bad_options(self):
        self.assertNotEqual(self.run_script("--version", "../oops").returncode, 0)
        self.assertNotEqual(self.run_script("--apply", "--check").returncode, 0)
        self.active.unlink()
        self.active.symlink_to(self.original)
        self.assertNotEqual(self.run_script("--apply").returncode, 0)

    def test_lock(self):
        (self.home / ".opencode/.rafex-update.lock").mkdir()
        self.assertNotEqual(self.run_script("--apply").returncode, 0)


if __name__ == "__main__":
    unittest.main()
