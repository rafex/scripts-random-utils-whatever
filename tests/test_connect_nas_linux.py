"""Pruebas del montaje TNAS con utilidades del sistema simuladas."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/network/connect_nas_linux.sh"


class ConnectNasLinux(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.state = self.root / "mounted-source"
        self.calls = self.root / "calls"
        self.mount_point = self.root / "mnt" / "tnas"
        self.config_home = self.root / "config"
        self.credentials_dir = self.config_home / "samba"
        self.credentials_dir.mkdir(parents=True)
        self.credentials = self.credentials_dir / "tnas.credentials"
        self.credentials.write_text("username=test-user\npassword=not-a-real-secret\n")
        self.credentials.chmod(0o644)
        self.credentials_dir.chmod(0o755)

        self._command("mountpoint", """#!/bin/bash
[[ -f \"$NAS_TEST_STATE\" ]]
""")
        self._command("findmnt", """#!/bin/bash
cat \"$NAS_TEST_STATE\"
""")
        self._command("mount.cifs", "#!/bin/bash\nexit 0\n")
        self._command("notify-send", "#!/bin/bash\nexit 0\n")
        self._command("sudo", """#!/bin/bash
if [[ \"$1\" == mkdir ]]; then
  shift
  exec /usr/bin/mkdir \"$@\"
fi
if [[ \"$1\" == mount ]]; then
  printf '%s\\n' \"$*\" >> \"$NAS_TEST_CALLS\"
  if [[ \"${NAS_TEST_MOUNT_FAIL:-0}\" == 1 ]]; then
    echo 'simulated CIFS failure' >&2
    exit 32
  fi
  printf '%s\\n' \"$4\" > \"$NAS_TEST_STATE\"
  exit 0
fi
echo \"unexpected sudo command: $*\" >&2
exit 98
""")

        self.env = os.environ.copy()
        self.env.update({
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "XDG_CONFIG_HOME": str(self.config_home),
            "NAS_MOUNT_POINT": str(self.mount_point),
            "NAS_TEST_STATE": str(self.state),
            "NAS_TEST_CALLS": str(self.calls),
        })
        for name in ("NAS_SMB", "NAS_CREDENTIALS", "NAS_SMB_VERSION", "NAS_UID", "NAS_GID",
                     "NAS_FILE_MODE", "NAS_DIR_MODE", "NAS_TEST_MOUNT_FAIL"):
            self.env.pop(name, None)

    def tearDown(self):
        self.temp.cleanup()

    def _command(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

    def _run(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                              text=True, capture_output=True, check=False)

    def test_mount_uses_smb_311_and_secures_default_credentials(self):
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SMB 3.1.1", result.stdout)
        self.assertEqual(self.state.read_text().strip(), "//192.168.3.56/rafex")
        self.assertEqual(self.credentials_dir.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.credentials.stat().st_mode & 0o777, 0o600)
        call = self.calls.read_text()
        self.assertIn("vers=3.1.1", call)
        self.assertIn("uid=", call)
        self.assertNotIn("not-a-real-secret", call)

    def test_same_share_is_idempotent(self):
        self.state.write_text("//192.168.3.56/rafex\n")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ya conectado", result.stdout)
        self.assertFalse(self.calls.exists())

    def test_different_existing_mount_is_left_untouched(self):
        self.state.write_text("//other-server/share\n")
        result = self._run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ya está ocupado", result.stderr)
        self.assertEqual(self.state.read_text().strip(), "//other-server/share")

    def test_mount_error_is_reported_and_preserves_status(self):
        self.env["NAS_TEST_MOUNT_FAIL"] = "1"
        result = self._run()
        self.assertEqual(result.returncode, 32)
        self.assertIn("simulated CIFS failure", result.stderr)

    def test_missing_credentials_fail_without_mounting(self):
        self.credentials.unlink()
        result = self._run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no existe un archivo regular", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_arguments_are_rejected(self):
        result = self._run("--help")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no acepta argumentos", result.stderr)


if __name__ == "__main__":
    unittest.main()
