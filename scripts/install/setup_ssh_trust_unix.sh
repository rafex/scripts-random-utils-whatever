#!/usr/bin/env bash
# shellcheck shell=bash
#
# Genera una clave SSH ed25519 local y, opcionalmente, instala solo la pública
# en authorized_keys de otro usuario. Compatible con macOS y Linux.
set -Eeuo pipefail
umask 077

ACTION="check"
TARGET="${SSH_TRUST_TARGET:-}"
KEY_PATH="${SSH_TRUST_KEY:-$HOME/.ssh/id_ed25519}"
COMMENT="${SSH_TRUST_COMMENT:-${USER:-user}@$(hostname -s 2>/dev/null || hostname)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  setup_ssh_trust_unix.sh --check
  setup_ssh_trust_unix.sh --plan [--target usuario@host]
  setup_ssh_trust_unix.sh --apply [--target usuario@host]

Opciones:
  --target usuario@host  Instalar la clave pública en ese host
  --key archivo          Ruta de la clave local (default: ~/.ssh/id_ed25519)
  --comment texto        Comentario de la clave nueva
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Generar clave y/o instalarla remotamente
  --print-public         Mostrar la clave pública y salir
  -h, --help             Mostrar esta ayuda

La clave privada nunca se copia ni se transmite. Si se crea una clave nueva,
ssh-keygen solicita su passphrase de forma interactiva.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        [[ $# -ge 2 ]] || die "--target requiere usuario@host"
        TARGET="$2"
        shift 2
        ;;
      --key)
        [[ $# -ge 2 ]] || die "--key requiere una ruta"
        KEY_PATH="$2"
        shift 2
        ;;
      --comment)
        [[ $# -ge 2 ]] || die "--comment requiere texto"
        COMMENT="$2"
        shift 2
        ;;
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --print-public) ACTION="print-public"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_supported_os() {
  case "$(uname -s)" in
    Darwin|Linux) ;;
    *) die "sistema operativo no soportado: $(uname -s)" ;;
  esac
  command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen no está instalado"
  [[ "$EUID" -ne 0 ]] || die "ejecuta el script como usuario normal, no como root"
}

public_key_path() {
  printf '%s.pub' "$KEY_PATH"
}

ensure_ssh_directory() {
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] crear ~/.ssh con permisos 700 si falta"
  else
    mkdir -p "$(dirname "$KEY_PATH")"
    chmod 700 "$(dirname "$KEY_PATH")"
  fi
}

generate_or_restore_public_key() {
  local public_path
  local temporary
  public_path="$(public_key_path)"

  if [[ -f "$KEY_PATH" ]]; then
    if [[ "$ACTION" == "apply" ]]; then
      chmod 600 "$KEY_PATH" 2>/dev/null || true
    fi
    if [[ ! -s "$public_path" ]]; then
      if [[ "$ACTION" == "plan" ]]; then
        info "[plan] regenerar la pública desde $KEY_PATH"
      else
        temporary="$(mktemp)"
        ssh-keygen -y -f "$KEY_PATH" > "$temporary"
        mv "$temporary" "$public_path"
        chmod 644 "$public_path"
        ok "clave pública regenerada: $public_path"
      fi
    fi
    return 0
  fi

  [[ ! -e "$public_path" ]] || die "existe $public_path pero falta la privada $KEY_PATH"
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] ssh-keygen -t ed25519 -a 64 -f $KEY_PATH"
  else
    ensure_ssh_directory
    info "generando clave ed25519; ssh-keygen solicitará la passphrase"
    ssh-keygen -t ed25519 -a 64 -f "$KEY_PATH" -C "$COMMENT"
    chmod 600 "$KEY_PATH"
    chmod 644 "$public_path"
    ok "clave creada: $KEY_PATH"
  fi
}

public_key() {
  local public_path
  public_path="$(public_key_path)"
  [[ -s "$public_path" ]] || die "no existe la clave pública; usa --apply primero"
  cat "$public_path"
}

print_local_status() {
  local public_path
  public_path="$(public_key_path)"
  echo
  echo -e "${BOLD}${CYAN}═══ Confianza SSH local ═══${RESET}"
  printf 'key=%s\n' "$KEY_PATH"
  if [[ -s "$KEY_PATH" ]]; then
    ok "clave privada presente"
  else
    warn "clave privada ausente"
  fi
  if [[ -s "$public_path" ]]; then
    ok "clave pública presente"
    printf 'fingerprint='; ssh-keygen -lf "$public_path" | awk '{print $2, $3}'
  else
    warn "clave pública ausente"
  fi
  if [[ -n "$TARGET" ]]; then
    printf 'target=%s\n' "$TARGET"
    if [[ -s "$public_path" ]] && ssh -o BatchMode=yes -o ConnectTimeout=6 "$TARGET" true >/dev/null 2>&1; then
      ok "el acceso SSH sin contraseña ya funciona hacia $TARGET"
    else
      warn "el acceso SSH sin contraseña aún no está confirmado hacia $TARGET"
    fi
  fi
}

install_remote_key() {
  local key
  key="$(public_key)"
  [[ -n "$TARGET" ]] || {
    info "no se indicó --target; solo se preparó la clave local"
    return 0
  }
  command -v ssh >/dev/null 2>&1 || die "ssh no está instalado"
  info "instalando solo la clave pública en $TARGET"
  printf '%s\n' "$key" | ssh -o ConnectTimeout=10 "$TARGET" '
    set -eu
    umask 077
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    authorized="$HOME/.ssh/authorized_keys"
    touch "$authorized"
    chmod 600 "$authorized"
    IFS= read -r public_key
    if grep -Fqx "$public_key" "$authorized"; then
      printf "SSH_PUBLIC_KEY_ALREADY_PRESENT\n"
    else
      printf "%s\n" "$public_key" >> "$authorized"
      printf "SSH_PUBLIC_KEY_INSTALLED\n"
    fi
  '
  ok "clave pública instalada o ya existente en $TARGET"
}

main() {
  parse_args "$@"
  require_supported_os

  if [[ "$ACTION" == "print-public" ]]; then
    public_key
    exit 0
  fi

  if [[ "$ACTION" == "check" ]]; then
    print_local_status
    exit 0
  fi

  ensure_ssh_directory
  generate_or_restore_public_key

  if [[ "$ACTION" == "plan" ]]; then
    [[ -n "$TARGET" ]] && info "[plan] enviar la clave pública a $TARGET mediante SSH"
    info "[plan] no se modificará ningún archivo"
    exit 0
  fi

  install_remote_key
  print_local_status
  info "clave pública:"
  public_key
}

main "$@"
