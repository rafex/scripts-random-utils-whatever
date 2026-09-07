"""Pruebas sin red ni cambios reales de sistema: python3 -m unittest discover -s tests.

configure_wwan_flame_oxxocel_linux.sh no expone una subcomando para invocar
find_modem_path()/find_modem_id() de forma aislada (el resto del script hace
una auditoría completa del sistema con systemctl/sudo/mmcli real), así que
estas pruebas extraen esas dos funciones tal cual están en el archivo real
(sed entre la firma y el `}` de cierre, sin copiarlas a mano, para que la
prueba nunca quede desincronizada del script) y las ejecutan en un arnés
mínimo con un `mmcli` simulado. Simétrico a
test_configure_wwan_oxxocel_linux.py, pero con la lógica de selección
invertida: este script busca el módem que NO sea Sierra Wireless.
"""
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/network/configure_wwan_flame_oxxocel_linux.sh"

SIERRA_FIRST = """    /org/freedesktop/ModemManager1/Modem/1 [Sierra Wireless, Incorporated] Sierra Wireless EM7455 Qualcomm Snapdragon X7 LTE-A
    /org/freedesktop/ModemManager1/Modem/0 [QUALCOMM INCORPORATED] 0
"""

SIERRA_SECOND = """    /org/freedesktop/ModemManager1/Modem/7 [Sierra Wireless, Incorporated] Sierra Wireless EM7455 Qualcomm Snapdragon X7 LTE-A
    /org/freedesktop/ModemManager1/Modem/9 [QUALCOMM INCORPORATED] 0
"""

FLAME_ONLY = """    /org/freedesktop/ModemManager1/Modem/4 [QUALCOMM INCORPORATED] 0
"""

SIERRA_ONLY = """    /org/freedesktop/ModemManager1/Modem/3 [Sierra Wireless, Incorporated] Sierra Wireless EM7455 Qualcomm Snapdragon X7 LTE-A
"""

NO_MODEMS = ""


def extract_functions(*names):
    text = SCRIPT.read_text()
    chunks = []
    for name in names:
        start = text.index(f"{name}() {{")
        end = text.index("\n}", start) + len("\n}")
        chunks.append(text[start:end])
    return "\n\n".join(chunks)


FUNCTIONS_UNDER_TEST = extract_functions("find_modem_path", "find_modem_id")
RAW_IP_RULE_FUNCTION = extract_functions("raw_ip_rule_content")


class FindModemId(unittest.TestCase):
    def run_with_listing(self, listing):
        with tempfile.TemporaryDirectory() as tmp:
            mock_bin = Path(tmp) / "bin"
            mock_bin.mkdir()
            mmcli_out = Path(tmp) / "mmcli_output"
            mmcli_out.write_text(listing)
            (mock_bin / "mmcli").write_text(
                "#!/bin/sh\n"
                f'cat "{mmcli_out}"\n'
            )
            (mock_bin / "mmcli").chmod(0o755)
            harness = Path(tmp) / "harness.sh"
            harness.write_text(
                "set -Eeuo pipefail\n"
                f"{FUNCTIONS_UNDER_TEST}\n"
                'find_modem_id || echo NONE\n'
            )
            return subprocess.run(
                ["bash", str(harness)],
                env={"PATH": f"{mock_bin}:/usr/bin:/bin"},
                capture_output=True, text=True,
            )

    def test_picks_non_sierra_when_sierra_listed_first(self):
        result = self.run_with_listing(SIERRA_FIRST)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "0")

    def test_picks_non_sierra_when_sierra_listed_second(self):
        # Regresión simétrica al fix de configure_wwan_oxxocel_linux.sh:
        # el orden de /org/.../Modem/<N> no es estable con dos módems
        # WWAN presentes.
        result = self.run_with_listing(SIERRA_SECOND)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "9")

    def test_flame_only(self):
        result = self.run_with_listing(FLAME_ONLY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "4")

    def test_falls_back_to_first_when_only_sierra_present(self):
        # Sin un segundo módem, no hay nada que excluir: se recurre a la
        # primera línea (aunque sea la EM7455) en vez de reportar "ninguno".
        result = self.run_with_listing(SIERRA_ONLY)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "3")

    def test_no_modems_reports_none(self):
        result = self.run_with_listing(NO_MODEMS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "NONE")


class RawIpUdevRule(unittest.TestCase):
    def test_matches_only_by_usb_vendor_product_not_by_driver(self):
        # Regresión: una versión anterior de esta regla combinaba
        # DRIVERS=="qmi_wwan" con ATTRS{idVendor}/ATTRS{idProduct} en la
        # misma línea. udev exige que todos los ATTRS{} de una regla
        # coincidan con el MISMO dispositivo ancestro; DRIVERS=="qmi_wwan"
        # coincide con el padre inmediato (la interfaz USB), mientras que
        # idVendor/idProduct viven un nivel más arriba (el dispositivo USB
        # completo) -- así que la regla nunca coincidía (confirmado en
        # vivo con `udevadm test`, sin RUN encolado). La regla debe usar
        # solo SUBSYSTEM=="net" + ATTRS{idVendor}/ATTRS{idProduct}.
        harness = f"{RAW_IP_RULE_FUNCTION}\nFLAME_USB_ID='05c6:9025'\nraw_ip_rule_content\n"
        result = subprocess.run(["bash", "-c", harness], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        line = result.stdout.strip()
        self.assertNotIn("DRIVERS==", line)
        self.assertIn('SUBSYSTEM=="net"', line)
        self.assertIn('ATTRS{idVendor}=="05c6"', line)
        self.assertIn('ATTRS{idProduct}=="9025"', line)
        self.assertIn("raw_ip", line)


if __name__ == "__main__":
    unittest.main()
