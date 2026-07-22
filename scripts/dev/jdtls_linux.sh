#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# jdtls_linux.sh
# Lanza Eclipse JDT Language Server para editores (Neovim, etc.).
# Requiere JDTLS instalado en /opt/github/eclipse.jdt.ls.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

JDTLS_HOME="${JDTLS_HOME:-/opt/github/eclipse.jdt.ls}"
JAVA_BIN="${JAVA_BIN:-java}"
CONFIG_DIR="$JDTLS_HOME/config_linux"
LAUNCHER_JAR="$(ls "$JDTLS_HOME"/plugins/org.eclipse.equinox.launcher_*.jar | head -n 1)"

exec "$JAVA_BIN" \
  -Declipse.application=org.eclipse.jdt.ls.core.id1 \
  -Dosgi.bundles.defaultStartLevel=4 \
  -Declipse.product=org.eclipse.jdt.ls.core.product \
  -Dlog.protocol=true \
  -Dlog.level=ALL \
  -jar "$LAUNCHER_JAR" \
  -configuration "$CONFIG_DIR" \
  -data "${1:-$HOME/.local/share/nvim/jdtls-workspace/default}"
