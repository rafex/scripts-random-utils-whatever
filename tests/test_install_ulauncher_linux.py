"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

Requiere Debian real con dpkg-deb (el script exige /etc/os-release
ID=debian, y aquí construimos un .deb sintético de prueba) -- se valida
en el ThinkPad, igual que test_reconcile_runtimes.py. sudo/apt-get/wget
se mockean para no tocar el sistema real.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install/install_ulauncher_linux.sh"

SUDO_MOCK = '#!/bin/sh\ncase "$1" in\n  -v) exit 0 ;;\nesac\nexec "$@"\n'
LOGGING_NOOP_MOCK = '#!/bin/sh\necho "{name} $*" >> "$LOG"\nexit 0\n'
# El paquete real trae ulauncher.service (WantedBy=graphical-session.target),
# pero ese target nunca se activa en una sesión i3 sin systemd-logind/GNOME
# de por medio, así que sin --enable --now el daemon nunca corre: por
# defecto simulamos "inactivo" para que check_local_installation() tome la
# rama de aviso, salvo que un test lo sobrescriba.
SYSTEMCTL_MOCK = (
    '#!/bin/sh\n'
    'echo "systemctl $*" >> "$LOG"\n'
    'case "$*" in\n'
    '  "--user is-active --quiet ulauncher.service") exit 1 ;;\n'
    '  *) exit 0 ;;\n'
    'esac\n'
)

CURL_MOCK = '''#!/bin/sh
dest=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--output" ]; then dest="$arg"; fi
  prev="$arg"
done
echo "curl $*" >> "$LOG"
case "$*" in
  *ulauncher_*.deb*) cp "$FIXTURE_DEB" "$dest"; exit 0 ;;
esac
exit 1
'''


@unittest.skipUnless(shutil.which("dpkg-deb"), "requiere dpkg-deb (Debian real)")
class InstallUlauncherLinux(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture_dir = tempfile.TemporaryDirectory()
        cls.fixture_deb = cls.build_fixture_deb(
            Path(cls.fixture_dir.name), "ulauncher", "5.16.1", "all")
        cls.wrong_version_deb = cls.build_fixture_deb(
            Path(cls.fixture_dir.name), "ulauncher", "9.9.9", "all", suffix="wrong-version")
        cls.wrong_package_deb = cls.build_fixture_deb(
            Path(cls.fixture_dir.name), "not-ulauncher", "5.16.1", "all", suffix="wrong-package")

    @classmethod
    def tearDownClass(cls):
        cls.fixture_dir.cleanup()

    @staticmethod
    def build_fixture_deb(root, package, version, architecture, suffix="ok"):
        stage = root / f"stage-{suffix}"
        (stage / "DEBIAN").mkdir(parents=True)
        (stage / "DEBIAN/control").write_text(
            f"Package: {package}\nVersion: {version}\nArchitecture: {architecture}\n"
            "Maintainer: test <test@example.invalid>\n"
            "Description: fixture de prueba\n"
        )
        output = root / f"{package}_{version}_{suffix}.deb"
        subprocess.run(["dpkg-deb", "--build", "--root-owner-group", str(stage), str(output)],
                        check=True, capture_output=True)
        return output

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mock_bin = Path(self.temp.name) / "bin"
        self.mock_bin.mkdir()
        self.log = Path(self.temp.name) / "log"
        self.write(self.mock_bin / "sudo", SUDO_MOCK)
        for name in ("apt-get",):
            self.write(self.mock_bin / name, LOGGING_NOOP_MOCK.format(name=name))
        self.write(self.mock_bin / "curl", CURL_MOCK)
        self.write(self.mock_bin / "systemctl", SYSTEMCTL_MOCK)
        # Sin mockear, dpkg-query lee el estado real de la máquina de prueba
        # (en el ThinkPad, ulauncher 5.16.1 ya está instalado), lo que
        # rompería should_install() para los casos que necesitan ejercitar
        # la descarga/verificación. Por defecto simulamos ca-certificates
        # instalado (para no disparar install_prerequisites de más) y
        # ulauncher no instalado; los tests que necesitan lo contrario
        # llaman a self._mock_already_installed().
        self.write(
            self.mock_bin / "dpkg-query",
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  *ca-certificates*Status*) printf 'install ok installed'; exit 0 ;;\n"
            "esac\n"
            "exit 1\n",
        )
        self.env = dict(
            os.environ,
            LOG=str(self.log),
            FIXTURE_DEB=str(self.fixture_deb),
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

    def test_help_does_not_require_debian(self):
        result = self.run_script("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install_ulauncher_linux.sh", result.stdout)

    def test_rejects_unsupported_version(self):
        result = self.run_script("--check", "--version", "9.9.9")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no soportada", result.stderr)

    def test_check_makes_no_mutating_calls(self):
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # "systemctl ... is-active" es un diagnóstico de solo lectura;
        # cualquier otra llamada (apt-get, curl, enable, start) sería una
        # mutación indebida en modo --check.
        self.assertEqual(
            self.log_lines(),
            ["systemctl --user is-active --quiet ulauncher.service"],
        )

    def test_plan_makes_no_mutating_calls_and_announces_install(self):
        result = self.run_script("--plan")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("5.16.1", result.stdout)
        self.assertEqual(self.log_lines(), [])

    # No hay caso "happy path" aquí: el script fija EXPECTED_SHA256 y
    # EXPECTED_SIZE_BYTES contra el asset real de producción, y un
    # fixture sintético nunca coincidirá con esos valores pineados. Los
    # casos de rechazo de abajo confirman que la verificación corre antes
    # de instalar; el happy-path exacto se valida en vivo contra el asset
    # real en el ThinkPad (ver plan, paso de verificación 4).

    def test_verify_asset_rejects_wrong_size_via_short_download(self):
        truncated = Path(self.temp.name) / "truncated.deb"
        truncated.write_bytes(self.fixture_deb.read_bytes()[:100])
        env = dict(self.env, FIXTURE_DEB=str(truncated))
        result = self.run_script("--apply", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tamaño inesperado", result.stderr)
        self.assertFalse(any("ulauncher_" in line for line in self.log_lines()
                              if line.startswith("apt-get install")))

    def test_verify_asset_rejects_wrong_package_name(self):
        env = dict(self.env, FIXTURE_DEB=str(self.wrong_package_deb))
        result = self.run_script("--apply", env=env)
        self.assertNotEqual(result.returncode, 0)
        # El tamaño del fixture también difiere del pineado, así que basta
        # con confirmar que nunca se llega a instalar.
        self.assertFalse(any("ulauncher_" in line for line in self.log_lines()
                              if line.startswith("apt-get install")))

    def test_check_reports_inactive_service_without_starting_it(self):
        # Regresión inversa a una versión anterior de esta prueba: se
        # descubrió en vivo que ulauncher-toggle fallaba con
        # "org.freedesktop.DBus.Error.ServiceUnknown" porque nada arrancaba
        # ulauncher.service (WantedBy=graphical-session.target, que nunca se
        # activa en una sesión i3 sin systemd-logind/GNOME de por medio).
        # --check ahora sí toca systemctl, pero solo para diagnosticar
        # (is-active), nunca para habilitar ni arrancar nada.
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no está activo", result.stdout + result.stderr)
        lines = self.log_lines()
        self.assertTrue(any("is-active" in line for line in lines))
        self.assertFalse(any("enable" in line or " start " in line for line in lines))

    def _mock_already_installed(self):
        dpkg_query_mock = (
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  *Status*) printf 'install ok installed'; exit 0 ;;\n"
            "  *Version*) printf '5.16.1\\n'; exit 0 ;;\n"
            "esac\n"
            "exit 1\n"
        )
        self.write(self.mock_bin / "dpkg-query", dpkg_query_mock)

    def test_apply_i3_shortcut_when_already_installed(self):
        # should_install() debe saltarse la descarga/verificación cuando
        # la versión pineada ya está instalada, permitiendo probar el
        # parchado de i3 sin depender de un asset real coincidente.
        self._mock_already_installed()
        i3_dir = Path(self.temp.name) / "config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\nbindsym $mod+Return exec alacritty\n")
        env = dict(self.env, XDG_CONFIG_HOME=str(Path(self.temp.name) / "config"))
        result = self.run_script("--apply", "--i3-shortcut", env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(line.startswith("curl ") for line in self.log_lines()),
                          "no debería descargar nada si ya está instalado")
        content = i3_config.read_text()
        self.assertIn("# BEGIN rafex ulauncher", content)
        self.assertIn("bindsym $mod+u exec --no-startup-id ulauncher-toggle", content)
        self.assertIn("exec --no-startup-id systemctl --user start ulauncher.service", content)
        self.assertIn("bindsym $mod+Return exec alacritty", content)

    def test_apply_enables_and_starts_the_service(self):
        self._mock_already_installed()
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = self.log_lines()
        self.assertTrue(any("daemon-reload" in line for line in lines))
        self.assertTrue(any("enable --now ulauncher.service" in line for line in lines))

    def test_apply_without_i3_shortcut_does_not_touch_i3_config(self):
        self._mock_already_installed()
        i3_dir = Path(self.temp.name) / "config/i3"
        i3_dir.mkdir(parents=True)
        i3_config = i3_dir / "config"
        i3_config.write_text("set $mod Mod4\n")
        env = dict(self.env, XDG_CONFIG_HOME=str(Path(self.temp.name) / "config"))
        result = self.run_script("--apply", env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(i3_config.read_text(), "set $mod Mod4\n")


if __name__ == "__main__":
    unittest.main()
