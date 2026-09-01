#!/usr/bin/env bash
# v1.0.0 - Configura colas CUPS idempotentes para Epson XP-241 y Xerox Phaser 3020.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
TARGET="all"
DEVICE_URI_OVERRIDE=""
REPLACE=0

usage() {
  cat <<'EOF'
Uso:
  configure_printers_linux.sh [--check|--plan|--apply|--status]
                              [--printer epson|xerox|all]
                              [--device-uri URI] [--replace]
  configure_printers_linux.sh --test-print --printer epson|xerox

Crea las colas Epson_XP_241 y Xerox_Phaser_3020 usando dispositivos USB,
IPP, IPPS o dnssd descubiertos por CUPS. La primera creación puede requerir
sudo; imprimir y escanear no lo requieren.
EOF
}

die() {
  printf '✗ ERROR: %s\n' "$*" >&2
  exit 1
}

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

require_linux_debian() {
  [[ "$(uname -s)" == "Linux" ]] || die 'este configurador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == debian || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este configurador requiere Debian o un derivado compatible'
}

require_cups() {
  local command_name
  for command_name in lpadmin lpinfo lpstat; do
    command -v "$command_name" >/dev/null 2>&1 \
      || die "falta $command_name; ejecuta just install-printers --apply"
  done
  lpstat -r >/dev/null 2>&1 \
    || die 'el planificador CUPS no responde; ejecuta just install-printers --apply'
}

queue_name() {
  case "$1" in
    epson) printf '%s\n' 'Epson_XP_241' ;;
    xerox) printf '%s\n' 'Xerox_Phaser_3020' ;;
    *) die "impresora desconocida: $1" ;;
  esac
}

printer_label() {
  case "$1" in
    epson) printf '%s\n' 'Epson XP-241' ;;
    xerox) printf '%s\n' 'Xerox Phaser 3020' ;;
    *) die "impresora desconocida: $1" ;;
  esac
}

description_for() {
  case "$1" in
    epson) printf '%s\n' 'Rafex Epson XP-241' ;;
    xerox) printf '%s\n' 'Rafex Xerox Phaser 3020' ;;
    *) die "impresora desconocida: $1" ;;
  esac
}

validate_uri() {
  local uri="$1"
  [[ -n "$uri" && "$uri" != *$'\n'* && "$uri" != *$'\r'* && "$uri" != *' '* ]] \
    || die 'URI de dispositivo vacía o inválida'
  [[ "$uri" =~ ^(usb|ipp|ipps|dnssd|socket|lpd):// ]] \
    || die "esquema URI no permitido: $uri"
  [[ "$uri" != *'@'* ]] || die 'no se permiten credenciales dentro de la URI'
}

discovery_lines() {
  lpinfo -v 2>/dev/null
}

matches_for() {
  local kind="$1"
  case "$kind" in
    epson)
      awk 'tolower($0) ~ /epson|04b8/ { print }' ;;
    xerox)
      awk 'tolower($0) ~ /xerox|phaser|0924/ { print }' ;;
    *) die "impresora desconocida: $kind" ;;
  esac
}

list_candidates() {
  local kind="$1" line uri
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    uri="$(awk '{print $2}' <<<"$line")"
    [[ -n "$uri" ]] || continue
    printf '%s\t%s\n' "$uri" "$line"
  done < <(discovery_lines | matches_for "$kind")
}

select_uri() {
  local kind="$1" count=0
  local -a candidates=()
  if [[ -n "$DEVICE_URI_OVERRIDE" ]]; then
    [[ "$TARGET" != all ]] || die '--device-uri requiere --printer epson o --printer xerox'
    validate_uri "$DEVICE_URI_OVERRIDE"
    printf '%s\n' "$DEVICE_URI_OVERRIDE"
    return 0
  fi
  mapfile -t candidates < <(list_candidates "$kind" | cut -f1 | sort -u)
  count="${#candidates[@]}"
  if (( count == 0 )); then
    return 1
  fi
  if (( count > 1 )); then
    warn "se detectaron varias URI para $(printer_label "$kind"); usa --device-uri"
    list_candidates "$kind" | while IFS=$'\t' read -r uri line; do
      printf '  %s  (%s)\n' "$uri" "$line" >&2
    done
    return 2
  fi
  validate_uri "${candidates[0]}"
  printf '%s\n' "${candidates[0]}"
}

find_model() {
  local kind="$1" uri="$2" model
  if [[ "$uri" =~ ^(ipp|ipps|dnssd):// ]]; then
    printf '%s\n' everywhere
    return 0
  fi
  case "$kind" in
    epson)
      model="$(lpinfo -m | awk 'tolower($0) ~ /xp[- _]?24[01]/ { print $1; exit }')"
      if [[ -z "$model" ]]; then
        model="$(lpinfo -m | awk 'tolower($0) ~ /esc[\/ -]?p[\/ -]?r|escpr/ { print $1; exit }')"
      fi
      ;;
    xerox)
      model="$(lpinfo -m | awk 'tolower($0) ~ /phaser[- _]?3020/ { print $1; exit }')"
      ;;
    *) die "impresora desconocida: $kind" ;;
  esac
  [[ -n "$model" ]] || die "no se encontró un PPD Debian para $(printer_label "$kind"); revisa lpinfo -m"
  printf '%s\n' "$model"
}

queue_exists() {
  lpstat -p "$1" >/dev/null 2>&1
}

queue_uri() {
  lpstat -v "$1" 2>/dev/null | sed -E 's/^device for [^:]+: //' | head -n1
}

show_discovery() {
  local kind="$1" line found=0
  printf '== %s ==\n' "$(printer_label "$kind")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    found=1
    printf '→ %s\n' "$line"
  done < <(list_candidates "$kind")
  if (( found == 0 )); then
    warn 'no se detecta el dispositivo; conéctalo por USB o asegúrate de que esté en la misma red'
  fi
}

configure_one() {
  local kind="$1" queue uri model current_uri description candidate
  local -a candidates=()
  queue="$(queue_name "$kind")"
  if queue_exists "$queue" && [[ -z "$DEVICE_URI_OVERRIDE" ]]; then
    current_uri="$(queue_uri "$queue")"
    mapfile -t candidates < <(list_candidates "$kind" | cut -f1 | sort -u)
    if (( ${#candidates[@]} == 0 )); then
      ok "$queue ya está configurada; se conserva aunque el dispositivo esté apagado"
      return 0
    fi
    for candidate in "${candidates[@]}"; do
      if [[ "$candidate" == "$current_uri" ]]; then
        ok "$queue ya está configurada: $current_uri"
        return 0
      fi
    done
  fi
  if ! uri="$(select_uri "$kind")"; then
    if [[ "$ACTION" == apply ]]; then
      warn "se omite $(printer_label "$kind"): no hay una URI única disponible"
    fi
    return 1
  fi
  model="$(find_model "$kind" "$uri")"
  description="$(description_for "$kind")"
  if queue_exists "$queue"; then
    current_uri="$(queue_uri "$queue")"
    if [[ "$current_uri" == "$uri" ]]; then
      ok "$queue ya está configurada: $uri"
      return 0
    fi
    if (( ! REPLACE )); then
      die "la cola $queue existe con otra URI; usa --replace solo si deseas recrearla"
    fi
    if [[ "$ACTION" == plan ]]; then
      info "[plan] eliminar y recrear $queue por conflicto de URI"
      return 0
    fi
    info "recreando $queue; pueden perderse trabajos pendientes de esa cola"
    sudo lpadmin -x "$queue"
  fi
  if [[ "$ACTION" == plan ]]; then
    info "[plan] crear $queue con URI $uri y modelo $model"
    return 0
  fi
  sudo lpadmin -p "$queue" -E -v "$uri" -m "$model" -D "$description"
  ok "cola configurada: $queue"
}

set_default_if_available() {
  local queue
  queue="$(queue_name xerox)"
  queue_exists "$queue" || return 0
  if [[ "$ACTION" == plan ]]; then
    info "[plan] establecer $queue como impresora predeterminada"
  else
    sudo lpadmin -d "$queue"
    ok "impresora predeterminada: $queue"
  fi
}

show_status() {
  printf '═══ Colas de impresión ═══\n'
  lpstat -p -d 2>/dev/null || warn 'no hay colas CUPS o el planificador no responde'
  lpstat -v 2>/dev/null || true
  printf '═══ Descubrimiento CUPS ═══\n'
  show_discovery epson
  show_discovery xerox
  printf '═══ Escáner SANE ═══\n'
  if command -v scanimage >/dev/null 2>&1; then
    scanimage -L 2>/dev/null || true
  else
    warn 'scanimage no está instalado; ejecuta just install-printers --apply'
  fi
}

test_print() {
  local queue test_page
  [[ "$TARGET" != all ]] || die '--test-print requiere --printer epson o --printer xerox'
  queue="$(queue_name "$TARGET")"
  queue_exists "$queue" || die "la cola $queue no existe; ejecuta configure-printers --apply"
  test_page="/usr/share/cups/data/testprint"
  [[ -r "$test_page" ]] || die "no existe la página de prueba CUPS: $test_page"
  lp -d "$queue" "$test_page"
  ok "página de prueba enviada a $queue sin sudo"
}

while (($#)); do
  case "$1" in
    --check) ACTION="check" ;;
    --plan|--dry-run) ACTION="plan" ;;
    --apply) ACTION="apply" ;;
    --status) ACTION="status" ;;
    --test-print) ACTION="test-print" ;;
    --printer)
      (($# >= 2)) || die 'falta el valor de --printer'
      TARGET="$2"; shift
      [[ "$TARGET" =~ ^(epson|xerox|all)$ ]] || die '--printer debe ser epson, xerox o all'
      ;;
    --device-uri)
      (($# >= 2)) || die 'falta el valor de --device-uri'
      DEVICE_URI_OVERRIDE="$2"; shift ;;
    --replace) REPLACE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
  shift
done

require_linux_debian
require_cups

case "$ACTION" in
  check)
    printf '═══ Check colas de impresión ═══\n'
    show_status
    ;;
  plan)
    printf '═══ Plan colas de impresión ═══\n'
    show_discovery epson
    show_discovery xerox
    if [[ "$TARGET" == all || "$TARGET" == epson ]]; then
      configure_one epson || true
    fi
    if [[ "$TARGET" == all || "$TARGET" == xerox ]]; then
      configure_one xerox || true
    fi
    set_default_if_available
    info 'no se escribirá nada en modo plan'
    ;;
  apply)
    command -v sudo >/dev/null 2>&1 || die 'falta sudo para --apply'
    sudo -v
    configured=0
    if [[ "$TARGET" == all || "$TARGET" == epson ]]; then
      configure_one epson && configured=$((configured + 1)) || true
    fi
    if [[ "$TARGET" == all || "$TARGET" == xerox ]]; then
      configure_one xerox && configured=$((configured + 1)) || true
    fi
    (( configured > 0 )) || die 'no se configuró ninguna impresora; conecta una o proporciona --device-uri'
    set_default_if_available
    ;;
  status) show_status ;;
  test-print) test_print ;;
esac
