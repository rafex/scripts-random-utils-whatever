"""Regresiones del binding del menú para los controles de i3."""
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install/install_i3_laptop_controls_linux.sh"


class I3LaptopControlsBinding(unittest.TestCase):
    def test_xf86tools_invokes_ratmenu_helper_directly(self):
        source = SCRIPT.read_text()
        self.assertIn(
            "bindsym XF86Tools exec --no-startup-id ~/.local/bin/rafex-ratmenu.sh",
            source,
        )
        self.assertNotIn("bindsym XF86Tools exec --no-startup-id sh -c", source)


if __name__ == "__main__":
    unittest.main()
