#!/usr/bin/env bash
# v1.0.0 - Instala y configura mDNS/Avahi con resolución .local y alcance limitado.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ACTION="check"
PACKAGES=(avahi-daemon libnss-mdns avahi-utils)
EXPECTED_NSS="mdns4_minimal [NOTFOUND=return]"
CONFIG_FILE="/etc/avahi/avahi-daemon.conf"
NSSWITCH_FILE="/etc/nsswitch.conf"
STAMP="$(date +%Y%m%d_%H%M%S)"

ALLOW_INTERFACES=""
TMP_FILES=()

cleanup() {
  local file
  for file in "${TMP_FILES[@]}"; do
    rm -f -- "$file"
  done
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso: install_mdns_linux.sh [--check|--plan|--apply|--status]

Instala Avahi y libnss-mdns. Publica solo el nombre del equipo en Wi-Fi/Ethernet,
resuelve nombres .local y mantiene WWAN fuera del alcance mDNS.
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
  [[ "$(uname -s)" == "Linux" ]] || die 'este instalador requiere Linux'
  [[ -r /etc/os-release ]] || die 'no se puede identificar el sistema operativo'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]] \
    || die 'este instalador requiere Debian o un derivado compatible'
}

package_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '
}

package_candidate() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null \
    | awk -F': ' '/^[[:space:]]*Candidate:/ { print $2; exit }'
}

report_packages() {
  local package_name candidate
  for package_name in "${PACKAGES[@]}"; do
    candidate="$(package_candidate "$package_name")"
    if package_installed "$package_name"; then
      ok "$package_name instalado"
    else
      warn "$package_name no está instalado"
    fi
    if [[ -n "$candidate" && "$candidate" != '(none)' ]]; then
      info "$package_name candidato APT: $candidate"
    else
      warn "$package_name no tiene candidato APT"
    fi
  done
}

validate_packages() {
  local package_name candidate missing=0
  for package_name in "${PACKAGES[@]}"; do
    if package_installed "$package_name"; then
      continue
    fi
    candidate="$(package_candidate "$package_name")"
    if [[ -z "$candidate" || "$candidate" == '(none)' ]]; then
      warn "sin candidato APT: $package_name"
      missing=1
    fi
  done
  (( missing == 0 )) || die 'faltan candidatos APT; revisa las fuentes Debian'
}

detect_interfaces() {
  local detected
  if [[ -n "$ALLOW_INTERFACES" ]]; then
    printf '%s\n' "$ALLOW_INTERFACES"
    return 0
  fi
  detected="$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
    | awk -F: '$2 == "wifi" || $2 == "ethernet" { print $1 }' \
    | paste -sd, -)"
  [[ -n "$detected" ]] || return 1
  printf '%s\n' "$detected"
}

validate_interface_list() {
  [[ "$1" =~ ^[[:alnum:]_.-]+(,[[:alnum:]_.-]+)*$ ]] \
    || die "lista de interfaces inválida: $1"
  if [[ "$1" =~ (^|,)wwp[^,]*($|,) || "$1" =~ (^|,)cdc-wdm[^,]*($|,) ]]; then
    die 'por seguridad no se permite publicar mDNS sobre la interfaz WWAN'
  fi
}

render_avahi_config() {
  local source_file="$1" destination="$2" interfaces="$3"
  awk -v interfaces="$interfaces" '
    BEGIN {
      section=""; server_allow=0; publish_workstation=0; publish_hinfo=0;
      publish_domain=0; publish_dns=0; publish_resolv=0
    }
    /^# BEGIN rafex-mdns$/ { skipping=1; next }
    /^# END rafex-mdns$/ { skipping=0; next }
    skipping { next }
    /^\[[^]]+\]$/ {
      if (section == "[server]") {
        if (!server_allow) print "allow-interfaces=" interfaces
      }
      if (section == "[publish]") {
        if (!publish_workstation) print "publish-workstation=no"
        if (!publish_hinfo) print "publish-hinfo=no"
        if (!publish_domain) print "publish-domain=no"
        if (!publish_dns) print "publish-dns-servers=no"
        if (!publish_resolv) print "publish-resolv-conf-dns-servers=no"
      }
      section=$0; print; next
    }
    section == "[server]" && /^[[:space:]]*allow-interfaces[[:space:]]*=/ {
      print "allow-interfaces=" interfaces; server_allow=1; next
    }
    section == "[publish]" && /^[[:space:]]*publish-workstation[[:space:]]*=/ {
      print "publish-workstation=no"; publish_workstation=1; next
    }
    section == "[publish]" && /^[[:space:]]*publish-hinfo[[:space:]]*=/ {
      print "publish-hinfo=no"; publish_hinfo=1; next
    }
    section == "[publish]" && /^[[:space:]]*publish-domain[[:space:]]*=/ {
      print "publish-domain=no"; publish_domain=1; next
    }
    section == "[publish]" && /^[[:space:]]*publish-dns-servers[[:space:]]*=/ {
      print "publish-dns-servers=no"; publish_dns=1; next
    }
    section == "[publish]" && /^[[:space:]]*publish-resolv-conf-dns-servers[[:space:]]*=/ {
      print "publish-resolv-conf-dns-servers=no"; publish_resolv=1; next
    }
    { print }
    END {
      if (section == "[server]" && !server_allow) print "allow-interfaces=" interfaces
      if (section == "[publish]") {
        if (!publish_workstation) print "publish-workstation=no"
        if (!publish_hinfo) print "publish-hinfo=no"
        if (!publish_domain) print "publish-domain=no"
        if (!publish_dns) print "publish-dns-servers=no"
        if (!publish_resolv) print "publish-resolv-conf-dns-servers=no"
      }
      print "# BEGIN rafex-mdns"
      print "# mDNS solo en interfaces locales; WWAN queda fuera por allow-interfaces."
      print "# END rafex-mdns"
    }
  ' "$source_file" > "$destination"
}

render_nsswitch() {
  local source_file="$1" destination="$2"
  awk -v nss="$EXPECTED_NSS" '
    BEGIN { changed=0 }
    /^hosts:/ {
      if ($0 ~ /(^|[[:space:]])mdns4?_minimal([[:space:]]|$)/) { print; changed=1; next }
      if ($0 ~ /[[:space:]]dns([[:space:]]|$)/) {
        sub(/[[:space:]]dns([[:space:]]|$)/, " " nss " dns")
      } else {
        $0 = $0 " " nss
      }
      changed=1
    }
    { print }
    END { if (!changed) print "hosts:          files " nss " dns" }
  ' "$source_file" > "$destination"
}

backup_system_file() {
  local source="$1" backup="$1.bak.$STAMP"
  sudo cp -p "$source" "$backup"
  info "respaldo creado: $backup"
}

apply_config_file() {
  local source="$1" target="$2" mode="$3" backup_needed=0
  if sudo test -e "$target"; then
    backup_needed=1
  fi
  if (( backup_needed )); then
    backup_system_file "$target"
  fi
  sudo install -o root -g root -m "$mode" "$source" "$target"
}

write_configuration() {
  local interfaces="$1" config_tmp nss_tmp current_config current_nss
  config_tmp="$(mktemp)"
  nss_tmp="$(mktemp)"
  TMP_FILES+=("$config_tmp" "$nss_tmp")

  current_config="$(mktemp)"
  current_nss="$(mktemp)"
  TMP_FILES+=("$current_config" "$current_nss")
  sudo cat "$CONFIG_FILE" 2>/dev/null | tee "$current_config" >/dev/null || :
  cat "$NSSWITCH_FILE" > "$current_nss"
  render_avahi_config "$current_config" "$config_tmp" "$interfaces"
  render_nsswitch "$current_nss" "$nss_tmp"

  if ! sudo test -f "$CONFIG_FILE" || ! sudo cmp -s "$config_tmp" "$CONFIG_FILE"; then
    apply_config_file "$config_tmp" "$CONFIG_FILE" 644
  else
    ok "sin cambios: $CONFIG_FILE"
  fi
  if ! cmp -s "$nss_tmp" "$NSSWITCH_FILE"; then
    backup_system_file "$NSSWITCH_FILE"
    sudo install -o root -g root -m 644 "$nss_tmp" "$NSSWITCH_FILE"
  else
    ok "sin cambios: $NSSWITCH_FILE"
  fi
}

show_status() {
  local hostname_local
  printf '═══ mDNS/Avahi ═══\n'
  report_packages
  if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    ok 'avahi-daemon activo'
  else
    warn 'avahi-daemon no está activo'
  fi
  if systemctl is-enabled --quiet avahi-daemon 2>/dev/null; then
    ok 'avahi-daemon habilitado al arrancar'
  else
    warn 'avahi-daemon no está habilitado'
  fi
  if grep -Eq '^hosts:.*mdns4?_minimal' "$NSSWITCH_FILE" 2>/dev/null; then
    ok 'resolución .local configurada en nsswitch'
  else
    warn 'nsswitch no contiene mdns4_minimal'
  fi
  if [[ -r "$CONFIG_FILE" ]] && grep -Eq '^allow-interfaces=' "$CONFIG_FILE"; then
    info "interfaces mDNS: $(grep -m1 '^allow-interfaces=' "$CONFIG_FILE" | cut -d= -f2-)"
  else
    warn 'Avahi no tiene una lista de interfaces local explícita'
  fi
  hostname_local="$(hostname --short 2>/dev/null).local"
  if getent hosts "$hostname_local" >/dev/null 2>&1; then
    ok "resolución local disponible: $hostname_local"
  else
    info "no se pudo resolver $hostname_local desde esta sesión; puede ser normal si no hay otro anuncio local"
  fi
  info 'no se publican workstation, HINFO, dominio ni servidores DNS'
}

check() {
  local interfaces issues=0
  printf '═══ Check mDNS ═══\n'
  report_packages
  interfaces="$(detect_interfaces || true)"
  if [[ -n "$interfaces" ]]; then
    validate_interface_list "$interfaces"
    info "interfaces locales previstas: $interfaces"
  else
    warn 'no se detectaron interfaces Wi-Fi/Ethernet; no se puede limitar Avahi todavía'
    issues=$((issues + 1))
  fi
  if grep -Eq '^hosts:.*mdns4?_minimal' "$NSSWITCH_FILE" 2>/dev/null; then
    ok 'nsswitch ya incluye resolución mDNS'
  else
    warn 'nsswitch necesita añadir mdns4_minimal'
  fi
  if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    ok 'avahi-daemon activo'
  else
    warn 'avahi-daemon inactivo'
  fi
  (( issues == 0 )) || return 1
}

plan() {
  local interfaces
  printf '═══ Plan mDNS ═══\n'
  validate_packages
  interfaces="$(detect_interfaces || true)"
  [[ -n "$interfaces" ]] || die 'no se detectaron interfaces Wi-Fi/Ethernet'
  validate_interface_list "$interfaces"
  info "instalar: ${PACKAGES[*]}"
  info "configurar Avahi solo en: $interfaces"
  info "añadir mdns4_minimal a nsswitch si falta"
  info 'publicar únicamente hostname.local; no publicar servicios ni DNS'
  info 'habilitar y reiniciar avahi-daemon; no se modificará NetworkManager ni WWAN'
  info 'no se escribirá nada en modo plan'
}

apply() {
  local interfaces
  command -v sudo >/dev/null 2>&1 || die 'sudo no está disponible'
  validate_packages
  interfaces="$(detect_interfaces || true)"
  [[ -n "$interfaces" ]] || die 'no se detectaron interfaces Wi-Fi/Ethernet'
  validate_interface_list "$interfaces"
  sudo -v
  info 'actualizando índices APT'
  sudo apt-get update
  info "instalando: ${PACKAGES[*]}"
  sudo apt-get install -y "${PACKAGES[@]}"
  write_configuration "$interfaces"
  sudo systemctl enable --now avahi-daemon
  sudo systemctl restart avahi-daemon
  ok 'mDNS configurado; WWAN permanece fuera de allow-interfaces'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --status) ACTION="status" ;;
      --interfaces)
        (($# >= 2)) || die '--interfaces requiere una lista'
        ALLOW_INTERFACES="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción no reconocida: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_linux_debian
  case "$ACTION" in
    check) check ;;
    plan) plan ;;
    apply) apply ;;
    status) show_status ;;
  esac
}

main "$@"
