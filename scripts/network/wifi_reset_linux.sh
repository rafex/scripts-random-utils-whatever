#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# wifi_reset_linux.sh
# Recarga el driver WiFi (wl) y reinicia la radio con nmcli.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

sudo modprobe -r wl
sudo modprobe wl
nmcli radio wifi off
sleep 2
nmcli radio wifi on
