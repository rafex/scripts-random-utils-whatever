#!/usr/bin/env python3
"""Panel GTK3 de acciones conocidas del perfil Rafex ThinkPad.

No acepta comandos escritos por el usuario y nunca se ejecuta como root.
"""
import os
import shutil
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib


HOME = os.path.expanduser("~")
BIN = os.path.join(HOME, ".local", "bin")


def tool(name):
    return shutil.which(name) or os.path.join(BIN, name)


def run_fixed(argv):
    """Lanza una acción de una lista fija; no usa shell ni entrada libre."""
    try:
        subprocess.Popen(argv, start_new_session=True)
    except OSError as exc:
        print(f"No se pudo iniciar {argv[0]}: {exc}", file=sys.stderr)


class RafexControlPanel(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.rafex.ControlPanel")
        self.window = None
        self.status_label = None

    def do_activate(self):
        if self.window is None:
            self.window = Gtk.ApplicationWindow(application=self)
            self.window.set_title("Panel de control Rafex · ThinkPad")
            self.window.set_default_size(760, 620)
            self.window.set_position(Gtk.WindowPosition.CENTER)
            self.window.connect("destroy", self._closed)
            self._build_ui()
        self.window.present()

    def _closed(self, _window):
        self.window = None

    def _build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        root.set_border_width(14)
        self.window.add(root)

        title = Gtk.Label()
        title.set_markup("<b>RAFEX · PANEL DE CONTROL</b>\nThinkPad X1 Yoga")
        title.set_xalign(0)
        root.pack_start(title, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        root.pack_start(scroller, True, True, 0)
        grid = Gtk.Grid(column_spacing=16, row_spacing=12)
        scroller.add(grid)

        self._section(grid, 0, 0, "Brillo y audio", [
            ("Pantalla −", [tool("brightness-notify.sh"), "down"]),
            ("Pantalla +", [tool("brightness-notify.sh"), "up"]),
            ("Teclado −", [tool("kbd-brightness-notify.sh"), "down"]),
            ("Teclado +", [tool("kbd-brightness-notify.sh"), "up"]),
            ("Volumen −", [tool("volume-notify.sh"), "down"]),
            ("Volumen +", [tool("volume-notify.sh"), "up"]),
            ("Silenciar audio", [tool("volume-notify.sh"), "mute"]),
            ("Micrófono", [tool("microphone-notify.sh"), "toggle"]),
        ])
        self._section(grid, 1, 0, "Red y dispositivos", [
            ("Wi-Fi", [tool("wifi-toggle.sh"), "toggle"]),
            ("WWAN", ["nmcli", "radio", "wwan", "on"]),
            ("Bluetooth", ["blueman-manager"]),
            ("Pantallas", ["arandr"]),
            ("Proyector", [tool("screen-projector.sh"), "--apply", "--mode", "next"]),
            ("Cámara", ["guvcview"]),
        ])
        self._section(grid, 0, 1, "Sesión", [
            ("Captura completa", [tool("screenshot.sh"), "--full"]),
            ("Captura de área", [tool("screenshot.sh"), "--select"]),
            ("Portapapeles", [tool("clipboard-menu.sh"), "--show"]),
            ("Tema", [tool("theme-toggle.sh"), "--toggle"]),
            ("Bloquear", [tool("lock-screen.sh"), "--mode", "solid"]),
            ("Abrir terminal", ["alacritty"]),
            ("Synaptic", ["synaptic-pkexec"]),
        ])
        self._section(grid, 1, 1, "Laboratorio y configuración", [
            ("Estado del sistema", ["alacritty", "-e", "btop"]),
            ("Máquinas virtuales", ["virt-manager", "--connect", "qemu:///session"]),
            ("Conky", [tool("conky-launch.sh"), "--reload"]),
            ("Configuración i3", ["alacritty", "-e", "vi", os.path.join(HOME, ".config", "i3", "config")]),
            ("Configuración Openbox", ["alacritty", "-e", "vi", os.path.join(HOME, ".config", "openbox", "rc.xml")]),
            ("Estado de seguridad", ["alacritty", "-e", "just", "audit-thinkpad", "--status"]),
        ])

        power = Gtk.Frame(label="Acciones sensibles")
        power_grid = Gtk.Grid(column_spacing=8, row_spacing=8)
        power.set_border_width(8)
        power.add(power_grid)
        for col, (label, command) in enumerate([
            ("Cerrar sesión", [tool("desktop-settings-menu.sh"), "logout"]),
            ("Suspender", [tool("desktop-settings-menu.sh"), "suspend"]),
            ("Hibernar", [tool("desktop-settings-menu.sh"), "hibernate"]),
            ("Reiniciar", [tool("desktop-settings-menu.sh"), "reboot"]),
            ("Apagar", [tool("desktop-settings-menu.sh"), "poweroff"]),
        ]):
            self._button(power_grid, col, 0, label, command, sensitive=True)
        grid.attach(power, 0, 2, 2, 1)

        self.status_label = Gtk.Label(label="Estado: listo")
        self.status_label.set_xalign(0)
        root.pack_start(self.status_label, False, False, 0)

    def _section(self, grid, column, row, title, actions):
        frame = Gtk.Frame(label=title)
        frame.set_border_width(8)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        frame.add(box)
        for label, command in actions:
            button = Gtk.Button(label=label)
            button.set_halign(Gtk.Align.FILL)
            button.connect("clicked", self._clicked, command, label)
            box.pack_start(button, False, False, 0)
        grid.attach(frame, column, row, 1, 1)

    def _button(self, grid, column, row, label, command, sensitive=False):
        button = Gtk.Button(label=label)
        button.set_sensitive(sensitive)
        button.connect("clicked", self._clicked, command, label)
        grid.attach(button, column, row, 1, 1)

    def _clicked(self, _button, command, label):
        if not command or not command[0]:
            self.status_label.set_text(f"{label}: herramienta no disponible")
            return
        run_fixed(command)
        self.status_label.set_text(f"Ejecutado: {label}")


if __name__ == "__main__":
    if os.geteuid() == 0:
        print("Este panel no debe ejecutarse como root.", file=sys.stderr)
        raise SystemExit(1)
    app = RafexControlPanel()
    raise SystemExit(app.run(sys.argv))
