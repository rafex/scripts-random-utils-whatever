#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# install_wifi_polkit_linux.sh
# Instala la regla PolicyKit para que usuarios del grupo netdev gestionen
# NetworkManager sin sudo. Debe ejecutarse con sudo.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RULE='/etc/polkit-1/rules.d/10-nm-wifi.rules'

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Ejecutar con sudo: sudo $0" >&2
  exit 1
fi

cat > "$RULE" << 'EOF'
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
      subject.isInGroup("netdev")) {
    return polkit.Result.YES;
  }
});
EOF

chmod 644 "$RULE"

if getent group netdev >/dev/null 2>&1; then
  if ! groups "$SUDO_USER" | grep -q netdev; then
    usermod -aG netdev "$SUDO_USER"
    echo "Usuario $SUDO_USER agregado al grupo netdev."
  fi
else
  groupadd netdev
  usermod -aG netdev "$SUDO_USER"
  echo "Grupo netdev creado y $SUDO_USER agregado."
fi

echo "Regla creada: $RULE"
echo "Listo. Cerrá sesión y volvé a entrar para que el grupo netdev tenga efecto."
