#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# screen_mirror_linux.sh
# Duplica la pantalla interna (LVDS1) en el monitor externo (HDMI1).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INTERNAL="${SCREEN_INTERNAL:-LVDS1}"
EXTERNAL="${SCREEN_EXTERNAL:-HDMI1}"

xrandr \
  --output "$INTERNAL" --same-as "$EXTERNAL" --auto \
  --output "$EXTERNAL" --auto
