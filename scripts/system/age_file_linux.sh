#!/usr/bin/env bash
# v1.0.0 - Cifra y descifra archivos con age sin exponer frases en argumentos.
set -Eeuo pipefail
umask 077

ACTION=""
INPUT=""
OUTPUT=""
FORCE=0
PASSPHRASE=0
RECIPIENTS=()
SSH_RECIPIENTS=()
IDENTITIES=()
TEMP_OUTPUT=""

die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }

usage() {
  cat <<'EOF'
Uso:
  age_file_linux.sh --check
  age_file_linux.sh --plan --encrypt --input archivo --output archivo.age \
    --recipient age1...
  age_file_linux.sh --encrypt --input archivo --output archivo.age \
    --recipient age1...
  age_file_linux.sh --encrypt --input archivo --output archivo.age --passphrase
  age_file_linux.sh --decrypt --input archivo.age --output archivo \
    --identity ~/.config/age/keys.txt

La frase de paso se solicita de forma interactiva; nunca se acepta como valor
de argumento ni se escribe en logs.
EOF
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

allowed_output() {
  case "$1" in
    "$HOME"/*|/tmp/*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  if [[ -n "$TEMP_OUTPUT" && -e "$TEMP_OUTPUT" ]]; then
    rm -f -- "$TEMP_OUTPUT"
  fi
}

validate_common() {
  [[ "$(uname -s)" == Linux ]] || die 'este helper requiere Linux'
  command -v age >/dev/null 2>&1 || die 'falta age; ejecuta just install-age-gopass --apply'
}

validate_paths() {
  local input_real output_real output_dir
  [[ -n "$INPUT" && -f "$INPUT" ]] || die 'el archivo de entrada no existe o no es regular'
  [[ -n "$OUTPUT" ]] || die 'falta --output'
  output_dir="$(dirname -- "$OUTPUT")"
  [[ -d "$output_dir" ]] || die 'el directorio de salida no existe; no se crea automáticamente'
  [[ ! -L "$OUTPUT" ]] || die 'la salida es un enlace simbólico; se rechaza por seguridad'
  allowed_output "$(absolute_path "$OUTPUT")" \
    || die 'la salida debe estar bajo HOME o /tmp'
  input_real="$(readlink -f -- "$INPUT")"
  output_real="$(readlink -m -- "$OUTPUT")"
  [[ "$input_real" != "$output_real" ]] || die 'entrada y salida no pueden ser el mismo archivo'
  if [[ -e "$OUTPUT" && "$FORCE" -ne 1 ]]; then
    die "la salida ya existe; usa --force de forma explícita"
  fi
}

validate_mode() {
  if [[ "$ACTION" == encrypt ]]; then
    (( ${#RECIPIENTS[@]} + ${#SSH_RECIPIENTS[@]} > 0 || PASSPHRASE == 1 )) \
      || die 'cifrado requiere --recipient, --ssh-recipient o --passphrase'
    local recipient ssh_recipient
    for recipient in "${RECIPIENTS[@]}"; do
      [[ "$recipient" =~ ^(age1|AGE-)[A-Za-z0-9]+$ ]] \
        || die 'un recipient age no tiene un formato válido'
    done
    for ssh_recipient in "${SSH_RECIPIENTS[@]}"; do
      [[ -f "$ssh_recipient" ]] || die "no existe el archivo recipient SSH: $ssh_recipient"
    done
  else
    local identity
    for identity in "${IDENTITIES[@]}"; do
      [[ -r "$identity" ]] || die "la identidad age no se puede leer: $identity"
    done
  fi
}

show_plan() {
  validate_common
  validate_paths
  validate_mode
  printf '═══ Plan age ═══\n'
  if [[ "$ACTION" == encrypt ]]; then
    info 'cifrar la entrada en un archivo age temporal y reemplazar atómicamente la salida'
    info "recipients age=${#RECIPIENTS[@]}, recipients SSH=${#SSH_RECIPIENTS[@]}"
    ((PASSPHRASE == 1)) && info 'solicitar frase de paso interactiva'
  else
    info 'descifrar la entrada con las identidades indicadas en un archivo temporal'
  fi
  info 'no se escribirá nada en modo plan'
}

encrypt_file() {
  local output_dir output_base
  local -a command_args
  output_dir="$(dirname -- "$OUTPUT")"
  output_base="$(basename -- "$OUTPUT")"
  TEMP_OUTPUT="$(mktemp "$output_dir/.${output_base}.tmp.XXXXXX")"
  command_args=(age)
  ((PASSPHRASE == 1)) && command_args+=(-p)
  local recipient ssh_recipient
  for recipient in "${RECIPIENTS[@]}"; do command_args+=(-r "$recipient"); done
  for ssh_recipient in "${SSH_RECIPIENTS[@]}"; do command_args+=(-R "$ssh_recipient"); done
  command_args+=(-o "$TEMP_OUTPUT" "$INPUT")
  "${command_args[@]}"
}

decrypt_file() {
  local output_dir output_base identity
  local -a command_args
  output_dir="$(dirname -- "$OUTPUT")"
  output_base="$(basename -- "$OUTPUT")"
  TEMP_OUTPUT="$(mktemp "$output_dir/.${output_base}.tmp.XXXXXX")"
  command_args=(age -d)
  for identity in "${IDENTITIES[@]}"; do command_args+=(-i "$identity"); done
  command_args+=(-o "$TEMP_OUTPUT" "$INPUT")
  "${command_args[@]}"
}

apply_operation() {
  validate_common
  validate_paths
  validate_mode
  trap cleanup EXIT
  if [[ "$ACTION" == encrypt ]]; then encrypt_file; else decrypt_file; fi
  chmod 600 -- "$TEMP_OUTPUT"
  mv -f -- "$TEMP_OUTPUT" "$OUTPUT"
  TEMP_OUTPUT=""
  ok "archivo procesado: $OUTPUT"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --encrypt) ACTION="encrypt" ;;
      --decrypt) ACTION="decrypt" ;;
      --input) (($# >= 2)) || die 'falta valor para --input'; INPUT="$2"; shift ;;
      --output|-o) (($# >= 2)) || die 'falta valor para --output'; OUTPUT="$2"; shift ;;
      --recipient|-r) (($# >= 2)) || die 'falta valor para --recipient'; RECIPIENTS+=("$2"); shift ;;
      --ssh-recipient|-R) (($# >= 2)) || die 'falta valor para --ssh-recipient'; SSH_RECIPIENTS+=("$2"); shift ;;
      --identity|-i) (($# >= 2)) || die 'falta valor para --identity'; IDENTITIES+=("$2"); shift ;;
      --passphrase|-p) PASSPHRASE=1 ;;
      --force) FORCE=1 ;;
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  if [[ "$ACTION" == check ]]; then
    validate_common
    printf '✓ age disponible: %s\n' "$(age --version 2>/dev/null || true)"
    return
  fi
  [[ "$ACTION" == encrypt || "$ACTION" == decrypt || "$ACTION" == plan ]] \
    || die 'debes indicar --encrypt, --decrypt, --check o --plan'
  if [[ "$ACTION" == plan ]]; then show_plan; else apply_operation; fi
}

main "$@"
