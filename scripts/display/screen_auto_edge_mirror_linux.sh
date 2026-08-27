#!/usr/bin/env bash
# Compatibilidad: conserva el nombre histórico y delega en el controlador único.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTROLLER="$SCRIPT_DIR/screen_projector_linux.sh"
[[ -x "$CONTROLLER" ]] || CONTROLLER="$SCRIPT_DIR/screen-projector.sh"
exec "$CONTROLLER" --apply --mode mirror "$@"
