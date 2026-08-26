#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# install_wifi_polkit_linux.sh
# Instala la regla PolicyKit para que usuarios del grupo netdev gestionen
# NetworkManager sin sudo. Debe ejecutarse con sudo.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RULE='/etc/polkit-1/rules.d/10-nm-wifi.rules'
TARGET_USER="${SUDO_USER:-}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Ejecutar con sudo: sudo $0" >&2
  exit 1
fi

if [[ -z "$TARGET_USER" || "$TARGET_USER" == root ]]; then
  echo "No se pudo determinar el usuario que invocó sudo." >&2
  echo "Ejecuta el script como: sudo $0" >&2
  exit 1
fi

cat > "$RULE" << 'EOF'
polkit.addRule(function(action, subject) {
  var allowed = [
    "org.freedesktop.NetworkManager.settings.modify.system",
    "org.freedesktop.NetworkManager.settings.modify.own",
    "org.freedesktop.NetworkManager.network-control",
    "org.freedesktop.NetworkManager.enable-disable-wifi",
    "org.freedesktop.NetworkManager.enable-disable-network",
    "org.freedesktop.NetworkManager.wifi.scan"
  ];
  if (subject.local && subject.active && subject.isInGroup("netdev") &&
      allowed.indexOf(action.id) >= 0) {
    return polkit.Result.YES;
  }
});
EOF

chmod 644 "$RULE"

if getent group netdev >/dev/null 2>&1; then
  if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx netdev; then
    usermod -aG netdev "$TARGET_USER"
    echo "Usuario $TARGET_USER agregado al grupo netdev."
  fi
else
  groupadd netdev
  usermod -aG netdev "$TARGET_USER"
  echo "Grupo netdev creado y $TARGET_USER agregado."
fi

echo "Regla creada: $RULE"
echo "Listo. Cerrá sesión y volvé a entrar para que el grupo netdev tenga efecto."
