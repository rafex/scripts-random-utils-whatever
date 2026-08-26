#!/bin/sh
# Helper de brillo para la barra de i3status.
echo "☀ $(brightnessctl -m | cut -d, -f4)"
