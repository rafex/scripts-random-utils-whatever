"""Verifica el modo de planificación y la protección del checkout de Reco."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/install/install_reco_linux.sh"
UPSTREAM = "https://github.com/ryonakano/reco.git"


class RecoInstaller(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.log = self.root / "commands.log"
        self._command("dpkg-query", "#!/bin/sh\necho 'install ok installed'\n")
        self._command("sudo", f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{self.log}'\nexit 0\n")
        self.env = os.environ.copy()
        self.env.update({
            "PATH": f"{self.bin}:{self.env.get('PATH', '')}",
            "HOME": str(self.home),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
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

    def test_plan_has_no_side_effects(self):
        result = self._run("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(UPSTREAM, result.stdout)
        self.assertIn("--update", result.stdout)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / ".local/share/src/reco").exists())

    def test_update_refuses_tracked_changes_before_fetch(self):
        source = self.home / ".local/share/src/reco"
        (source / ".git").mkdir(parents=True)
        git_log = self.root / "git.log"
        self._command("git", f'''#!/bin/sh
printf '%s\\n' "$*" >> '{git_log}'
case "$*" in
  "-C {source} remote get-url origin") printf '%s\\n' '{UPSTREAM}' ;;
  "-C {source} branch --show-current") printf 'main\\n' ;;
  "-C {source} diff --quiet --ignore-submodules --") exit 1 ;;
  "-C {source} diff --cached --quiet --ignore-submodules --") exit 0 ;;
  *) exit 3 ;;
esac
''')
        result = self._run("--update")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cambios rastreados", result.stderr)
        self.assertNotIn("fetch", git_log.read_text())


if __name__ == "__main__":
    unittest.main()
