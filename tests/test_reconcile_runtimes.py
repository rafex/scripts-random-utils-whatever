"""Pruebas sin red ni cambios en instalaciones reales: python3 -m unittest discover -s tests."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install/reconcile_runtimes_linux.sh"

REGISTRY_ROW = "{tool}\t{provider}\t{version}\t{path}\t{checksum}\t{source}\n"

# Mock de mise: `link --force <id> <ruta>` reproduce fielmente lo que hace
# mise de verdad (confirmado en producción) — reemplaza
# installs/<tool>/<version> por un symlink hacia <ruta>, incluso si antes
# era un directorio real. Se puede desactivar con MOCK_MISE_LINK_NOOP=1
# para aislar pruebas que necesitan que la ruta legacy siga siendo un
# directorio real al momento de validar (protección original, sin relink).
MISE_MOCK = '''#!/bin/bash
case "$1" in
  link)
    shift
    [[ "$1" == --force ]] && shift
    id="$1"; target="$2"
    if [[ -z "${MOCK_MISE_LINK_NOOP:-}" ]]; then
      tool="${id%%@*}"; ver="${id#*@}"
      dir="$HOME/.local/share/mise/installs/$tool"
      mkdir -p "$dir"
      rm -rf -- "$dir/$ver"
      ln -s -- "$target" "$dir/$ver"
    fi
    ;;
  where)
    shift
    if [[ "$1" == "${MOCK_MISE_WHERE_ID:-}" && -n "${MOCK_MISE_WHERE:-}" ]]; then
      printf '%s\\n' "$MOCK_MISE_WHERE"
    fi
    ;;
esac
exit 0
'''


class ReconcileRuntimes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.mock_bin = self.home / ".local/bin"
        self.mock_bin.mkdir(parents=True)
        self.executable(self.mock_bin / "mise", MISE_MOCK)
        self.registry = self.home / ".local/share/rafex-runtimes/registry.tsv"
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            PATH=f"{self.mock_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
        )
        for var in ("MOCK_MISE_WHERE_ID", "MOCK_MISE_WHERE", "MOCK_MISE_LINK_NOOP"):
            self.env.pop(var, None)

    def executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)

    def register(self, tool, provider, version, path):
        self.registry.parent.mkdir(parents=True, exist_ok=True)
        with self.registry.open("a") as fh:
            fh.write(REGISTRY_ROW.format(
                tool=tool, provider=provider, version=version, path=path,
                checksum="deadbeef", source="https://example.invalid",
            ))

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], env=self.env,
                               capture_output=True, text=True)

    def test_purges_and_immediately_relinks_legacy_symlink(self):
        # Simula el estado real encontrado en producción: integrate_registry()
        # ya corrió antes (mise link --force) y convirtió la ruta legacy en
        # un symlink hacia el reemplazo propio. Verifica también que, tras
        # purgar, el segundo integrate_registry() (agregado en este fix)
        # deja node resoluble de nuevo en la misma corrida.
        replacement = self.home / ".local/share/node-runtimes/node-v24.20.0-linux-x64"
        self.executable(replacement / "bin/node", "#!/bin/sh\nexit 0\n")
        self.register("node", "nodejs", "24.20.0", replacement)

        legacy = self.home / ".local/share/mise/installs/node/24.20.0"
        legacy.parent.mkdir(parents=True)
        legacy.symlink_to(replacement)

        result = self.run_script("--apply", "--purge-legacy")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(replacement.is_dir())
        self.assertTrue((replacement / "bin/node").exists())
        # La ruta legacy debe seguir resolviendo (fue purgada y re-enlazada
        # en el mismo paso), no quedar simplemente borrada.
        self.assertTrue(legacy.is_symlink())
        self.assertEqual(os.path.realpath(legacy), os.path.realpath(replacement))

    def test_refuses_legacy_path_still_a_real_active_install(self):
        # Directorio legacy real (no symlink) que mise todavía reporta como
        # activo: debe seguir protegido, sin importar el fix anterior.
        # MOCK_MISE_LINK_NOOP aísla esta prueba de integrate_registry() para
        # que la ruta legacy siga siendo un directorio real al validar.
        self.env["MOCK_MISE_LINK_NOOP"] = "1"
        replacement = self.home / ".local/share/build-runtimes/maven/3.9.16"
        self.executable(replacement / "bin/mvn", "#!/bin/sh\nexit 0\n")
        self.register("maven", "official", "3.9.16", replacement)

        legacy = self.home / ".local/share/mise/installs/maven/3.9.16"
        legacy.mkdir(parents=True)
        (legacy / "bin").mkdir()
        (legacy / "bin/mvn").write_text("#!/bin/sh\nexit 0\n")

        self.env["MOCK_MISE_WHERE_ID"] = "maven@3.9.16"
        self.env["MOCK_MISE_WHERE"] = str(legacy)

        result = self.run_script("--apply", "--purge-legacy")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("todavía es el runtime activo", result.stderr)
        self.assertTrue(legacy.is_dir())
        self.assertFalse(legacy.is_symlink())

    def test_purges_legacy_alias_pointing_at_a_different_registered_version(self):
        # Reproduce el caso real encontrado en el ThinkPad: dos versiones de
        # graalvm-community registradas a la vez (se instaló una nueva
        # mientras la vieja seguía presente). El alias legacy "25" de mise
        # apunta a la versión NUEVA mientras que "25.0.2" apunta a la VIEJA;
        # replacement_for() solo devuelve la primera fila (la vieja), así
        # que sin replacement_targets_for() (que compara contra TODAS las
        # filas registradas) esto fallaba con "destino inesperado".
        old = self.home / ".local/share/java-runtimes/graalvm-community/jdk-25.0.2-jdk"
        new = self.home / ".local/share/java-runtimes/graalvm-community/25.3.4.1-jdk"
        self.executable(old / "bin/java", "#!/bin/sh\nexit 0\n")
        self.executable(new / "bin/java", "#!/bin/sh\nexit 0\n")
        self.register("java", "graalvm-community", "25.0.2", old)
        self.register("java", "graalvm-community", "25.3.4.1", new)

        installs = self.home / ".local/share/mise/installs/graalvm"
        installs.mkdir(parents=True)
        (installs / "25.0.2").symlink_to(old)
        (installs / "25.0").symlink_to(old)
        (installs / "25").symlink_to(new)

        result = self.run_script("--apply", "--purge-legacy")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("destino inesperado", result.stderr)
        # La versión exacta registrada (25.0.2) se re-enlaza tras el purge;
        # los alias parciales ("25", "25.0") no los recrea este script —
        # eso lo gestiona mise en su próximo install/use/link real.
        self.assertTrue((installs / "25.0.2").is_symlink())
        self.assertEqual(os.path.realpath(installs / "25.0.2"), os.path.realpath(old))


if __name__ == "__main__":
    unittest.main()
