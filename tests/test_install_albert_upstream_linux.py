"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

git, cmake, sudo, apt-get, dpkg-query y nproc se mockean vía PATH para no
clonar/compilar nada real ni tocar el sistema. `uname` se mockea para poder
ejercitar require_base() en cualquier plataforma. El caso feliz de
clonar+compilar+instalar de verdad se valida en vivo en la ThinkPad (una
compilación real de Qt6 no es razonable de simular por completo aquí).
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install/install_albert_upstream_linux.sh"

VERSION = "v35.1.0"
EXPECTED_COMMIT = "21d0b78dafc53d3ea9aebd139b26bf1ae8ea115b"
REPO_URL = "https://github.com/albertlauncher/albert.git"

UNAME_MOCK = '#!/bin/sh\n[ "$1" = "-s" ] && echo Linux || echo unknown\n'
SUDO_MOCK = '#!/bin/sh\ncase "$1" in\n  -v) exit 0 ;;\nesac\nexec "$@"\n'
LOGGING_NOOP_MOCK = '#!/bin/sh\necho "{name} $*" >> "$LOG"\nexit 0\n'
NPROC_MOCK = '#!/bin/sh\necho 4\n'

GIT_MOCK = f'''#!/bin/sh
echo "git $*" >> "$LOG"
case "$*" in
  clone*)
    dest=$(echo "$*" | awk '{{print $NF}}')
    mkdir -p "$dest/.git"
    exit 0
    ;;
  *"rev-parse HEAD")
    echo "$GIT_COMMIT"
    exit 0
    ;;
  *"rev-parse --short HEAD")
    echo "$GIT_COMMIT" | cut -c1-7
    exit 0
    ;;
  *"config --get remote.origin.url")
    echo "$GIT_REMOTE"
    exit 0
    ;;
  *"status --porcelain --ignore-submodules=all")
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'''

CMAKE_MOCK = '''#!/bin/sh
echo "cmake $*" >> "$LOG"
case "$1" in
  -S)
    shift
    shift
    build=""
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "-B" ]; then build="$arg"; fi
      prev="$arg"
    done
    mkdir -p "$build"
    exit 0
    ;;
  --build)
    build="$2"
    mkdir -p "$build/bin"
    printf '#!/bin/sh\\necho %s\\n' "$ALBERT_VERSION" > "$build/bin/albert"
    chmod +x "$build/bin/albert"
    exit 0
    ;;
  --install)
    build="$2"
    prefix="$HOME/.local"
    mkdir -p "$prefix/bin"
    cp "$build/bin/albert" "$prefix/bin/albert"
    exit 0
    ;;
  *) exit 0 ;;
esac
'''


class InstallAlbertUpstreamLinux(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home"
        self.home.mkdir()
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        self.log = Path(self.temp.name) / "log"
        self.write(self.mock_bin / "uname", UNAME_MOCK)
        self.write(self.mock_bin / "sudo", SUDO_MOCK)
        self.write(self.mock_bin / "nproc", NPROC_MOCK)
        self.write(self.mock_bin / "git", GIT_MOCK)
        self.write(self.mock_bin / "cmake", CMAKE_MOCK)
        for name in ("apt-get",):
            self.write(self.mock_bin / name, LOGGING_NOOP_MOCK.format(name=name))
        # Por defecto todos los paquetes de build "no instalados"; los tests
        # que necesitan lo contrario sobrescriben este mock.
        self.write(self.mock_bin / "dpkg-query", "#!/bin/sh\nexit 1\n")
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            LOG=str(self.log),
            GIT_COMMIT=EXPECTED_COMMIT,
            GIT_REMOTE=REPO_URL,
            ALBERT_VERSION=VERSION,
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
        result = subprocess.run(["bash", str(SCRIPT), "--help"], env=dict(os.environ),
                                 capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install_albert_upstream_linux.sh", result.stdout)

    def test_rejects_selecting_two_actions(self):
        result = self.run_script("--check", "--plan")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("una sola acción", result.stderr)

    def test_check_makes_no_mutating_calls(self):
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.log_lines(), [])

    def test_plan_lists_all_missing_packages_without_mutating(self):
        result = self.run_script("--plan")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(VERSION, result.stdout)
        self.assertIn(EXPECTED_COMMIT, result.stdout)
        self.assertIn("qt6-base-dev", result.stdout)
        self.assertEqual(self.log_lines(), [])

    def test_plan_reports_no_missing_packages_when_all_installed(self):
        self.write(self.mock_bin / "dpkg-query",
                    "#!/bin/sh\nprintf 'install ok installed'\nexit 0\n")
        result = self.run_script("--plan")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("(ninguna)", result.stdout)

    def test_apply_installs_only_the_missing_packages(self):
        dpkg_query_mock = (
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  *cmake*) printf 'install ok installed'; exit 0 ;;\n"
            "esac\n"
            "exit 1\n"
        )
        self.write(self.mock_bin / "dpkg-query", dpkg_query_mock)
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        install_lines = [l for l in self.log_lines() if l.startswith("apt-get install")]
        self.assertEqual(len(install_lines), 1)
        self.assertNotIn("cmake", install_lines[0].split())
        self.assertIn("git", install_lines[0])

    def test_apply_produces_working_binary(self):
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        bin_target = self.home / ".local/bin/albert"
        self.assertTrue(bin_target.exists())
        version_output = subprocess.run([str(bin_target), "--version"],
                                         capture_output=True, text=True)
        self.assertEqual(version_output.stdout.strip(), VERSION)

    def test_apply_rejects_unexpected_commit(self):
        env = dict(self.env, GIT_COMMIT="0000000000000000000000000000000000000000")
        result = self.run_script("--apply", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("commit inesperado", result.stderr)
        self.assertFalse((self.home / ".local/bin/albert").exists())

    def test_apply_i3_shortcut_adds_bindsym_pointing_at_installed_binary(self):
        i3_dir = self.home / ".config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\nbindsym $mod+Return exec alacritty\n")
        result = self.run_script("--apply", "--i3-shortcut")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        content = i3_config.read_text()
        self.assertIn("# BEGIN rafex albert", content)
        self.assertIn("bindsym $mod+a exec --no-startup-id", content)
        self.assertIn(".local/bin/albert show", content)
        self.assertIn("bindsym $mod+Return exec alacritty", content)

    def test_apply_without_i3_shortcut_does_not_touch_i3_config(self):
        i3_dir = self.home / ".config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\n")
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(i3_config.read_text(), "set $mod Mod4\n")

if __name__ == "__main__":
    unittest.main()
