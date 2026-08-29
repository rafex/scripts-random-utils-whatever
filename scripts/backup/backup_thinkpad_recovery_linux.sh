#!/usr/bin/env bash
# shellcheck shell=bash
#
# Crea una instantánea segura y una copia curada del estado de una ThinkPad.
# El destino debe ser el SSD externo montado con etiqueta ssd_rafex_1.
set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-${0:-}}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
TARGET_USER="${SUDO_USER:-${USER:-}}"
DESTINATION_BASE="${THINKPAD_BACKUP_ROOT:-/run/media/${TARGET_USER}/ssd_rafex_1}"
EXPECTED_LABEL="ssd_rafex_1"
MODE="check"
STAMP="$(date +%Y%m%d_%H%M%S)"
STAGE=""
FINAL_DIR=""
FINAL_ARCHIVE=""

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() { printf '%b→%b %s\n' "${CYAN}${BOLD}" "$RESET" "$*"; }
success() { printf '%b✓%b %s\n' "${GREEN}${BOLD}" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "${YELLOW}${BOLD}" "$RESET" "$*" >&2; }
fatal() { printf '%b✗ ERROR:%b %s\n' "${RED}${BOLD}" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  $0 --check
  $0 --plan
  $0 --apply

Opciones:
  --check       Audita destino y fuentes sin crear archivos (default).
  --plan        Muestra el respaldo previsto sin modificar nada.
  --apply       Crea el respaldo en el SSD externo validado.
  -h, --help    Muestra esta ayuda.

Destino fijo:
  $DESTINATION_BASE

El destino debe estar montado y tener la etiqueta: $EXPECTED_LABEL
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) MODE="check"; shift ;;
      --plan|--dry-run) MODE="plan"; shift ;;
      --apply) MODE="apply"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fatal "argumento desconocido: $1" ;;
    esac
  done
}

require_commands() {
  local command
  [[ "$(uname -s)" == "Linux" ]] || fatal "este script solo funciona en Linux"
  [[ "$EUID" -ne 0 ]] || fatal "ejecuta el script como rafex; el script solicita sudo internamente"
  [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || fatal "ejecuta el script como el usuario de la laptop, no como root"
  for command in awk cp date df diff file find findmnt grep lsblk mkdir mktemp mountpoint sha256sum sort tar uname; do
    command -v "$command" >/dev/null 2>&1 || fatal "falta la herramienta requerida: $command"
  done
  [[ -d "$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st" ]] || \
    fatal "no se encontró el perfil ThinkPad en $REPO_ROOT"
}

destination_source() {
  findmnt -no SOURCE --target "$DESTINATION_BASE" 2>/dev/null || true
}

destination_label() {
  local source
  source="$(destination_source)"
  [[ -n "$source" ]] || return 0
  lsblk -no LABEL "$source" 2>/dev/null | head -n 1 | sed 's/[[:space:]]*$//' || true
}

validate_destination() {
  local source label filesystem available
  if [[ ! -d "$DESTINATION_BASE" ]]; then
    warn "no existe el punto de montaje: $DESTINATION_BASE"
    return 1
  fi
  if ! mountpoint -q "$DESTINATION_BASE"; then
    warn "el destino no está montado: $DESTINATION_BASE"
    return 1
  fi

  source="$(destination_source)"
  label="$(destination_label)"
  filesystem="$(findmnt -no FSTYPE --target "$DESTINATION_BASE" 2>/dev/null || true)"
  available="$(df -Pk "$DESTINATION_BASE" | awk 'NR == 2 {print $4}')"
  info "destino=$DESTINATION_BASE"
  info "dispositivo=${source:-desconocido} etiqueta=${label:-ausente} fs=${filesystem:-desconocido} espacio_disponible=${available:-desconocido} KB"

  [[ "$label" == "$EXPECTED_LABEL" ]] || {
    warn "la etiqueta del destino no coincide; se esperaba $EXPECTED_LABEL"
    return 1
  }
  return 0
}

show_plan() {
  cat <<EOF
Plan de respaldo (sin cambios):
  destino:       $DESTINATION_BASE
  directorio:    $DESTINATION_BASE/rafex-thinkpad-recovery-$STAMP/
  archivo:       $DESTINATION_BASE/rafex-thinkpad-recovery-$STAMP.tar.gz
  fuente perfil: $REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st/

Se incluirán configuraciones de usuario, scripts activos, plugins TPM,
runtimes manuales, inventarios del sistema, configuraciones protegidas de
referencia y una copia curada del perfil ThinkPad.

Se excluirán claves SSH, perfiles Wi-Fi, credenciales Git, cookies, keyrings
privados, caches, logs privados y el contenido de ~/.local/share/mise/installs.
fstab, crypttab y GRUB se guardarán solo como referencia y no se restaurarán
automáticamente.
EOF
}

record_exclusion() {
  printf '%s\n' "$*" >> "$STAGE/EXCLUSIONS.md"
}

copy_text_sanitized() {
  local source="$1" destination="$2"
  mkdir -p "$(dirname "$destination")"
  sed -E \
    -e '/-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----/,/-----END ([A-Z0-9 ]+ )?PRIVATE KEY-----/d' \
    -e 's/^([[:space:]]*(export[[:space:]]+)?[A-Za-z_]*(PASSWORD|PASSWD|SECRET|TOKEN|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY)[A-Za-z_]*[[:space:]]*=[[:space:]]*).*/\1<REDACTED_BY_BACKUP>/I' \
    -e 's/([?&](password|passwd|token|secret|api[_-]?key|access[_-]?key)=)[^&[:space:]]+/\1<REDACTED_BY_BACKUP>/Ig' \
    "$source" > "$destination"
}

# exFAT no soporta propietario ni permisos Unix. El contenido del respaldo
# debe seguir siendo portable; la restauración en Linux reaplicará permisos.
copy_portable() {
  cp -L --no-preserve=mode,ownership -- "$@"
}

copy_portable_tree() {
  cp -RL --no-preserve=mode,ownership -- "$@"
}

is_sensitive_path() {
  local path="$1"
  case "$path" in
    */.ssh/*|*/.netrc|*/.npmrc|*/.pypirc|*/.git-credentials|*/.aws/*|*/.gnupg/*|*/.config/gh/*|*/.config/pulse/cookie|*/.local/share/keyrings/*|*/system-connections/*|*/apt/auth.conf*)
      return 0 ;;
    *authorized_keys*|*known_hosts*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*|*.nmconnection|*credentials*|*secret*|*token*)
      return 0 ;;
  esac
  return 1
}

copy_user_path() {
  local source="$1" destination="$STAGE/user/$2"
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    record_exclusion "AUSENTE: $source"
    return 0
  fi
  if is_sensitive_path "$source"; then
    record_exclusion "EXCLUIDO (sensible): $source"
    return 0
  fi

  if [[ -d "$source" && ! -L "$source" ]]; then
    while IFS= read -r -d '' item; do
      local item_relative item_destination
      item_relative="${item#"$source"/}"
      item_destination="$destination/$item_relative"
      if is_sensitive_path "$item" || [[ "$(basename "$item")" == *.bak.* ]]; then
        record_exclusion "EXCLUIDO: $item"
        continue
      fi
      if [[ -d "$item" && ! -L "$item" ]]; then
        mkdir -p "$item_destination"
      elif [[ -f "$item" ]]; then
        mkdir -p "$(dirname "$item_destination")"
        if file --brief --mime-type "$item" 2>/dev/null | grep -q '^text/'; then
          copy_text_sanitized "$item" "$item_destination"
        else
          copy_portable "$item" "$item_destination"
        fi
      fi
    done < <(find "$source" -mindepth 1 -print0)
  elif [[ -f "$source" ]]; then
    if file --brief --mime-type "$source" 2>/dev/null | grep -q '^text/'; then
      copy_text_sanitized "$source" "$destination"
    else
      mkdir -p "$(dirname "$destination")"
      copy_portable "$source" "$destination"
    fi
  else
    record_exclusion "OMITIDO (tipo no soportado): $source"
  fi
}

copy_system_path() {
  local source="$1" destination="$STAGE/system/$2"
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    record_exclusion "AUSENTE (sistema): $source"
    return 0
  fi
  mkdir -p "$(dirname "$destination")"
  sudo cp -L --no-preserve=mode,ownership -- "$source" "$destination"
}

write_inventory() {
  local inventory="$1"
  shift
  {
    printf '# Inventario generado %s\n\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    "$@"
  } > "$STAGE/metadata/$inventory" 2>&1 || true
}

write_privileged_inventory() {
  local inventory="$1"
  shift
  {
    printf '# Inventario privilegiado generado %s\n\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
    sudo "$@"
  } > "$STAGE/metadata/$inventory" 2>&1 || true
}

copy_user_files() {
  local path
  for path in \
    .bashrc \
    .profile \
    .Xresources \
    .tmux.conf \
    .config/i3 \
    .config/i3status \
    .config/alacritty \
    .config/rofi \
    .config/dunst \
    .config/picom \
    .config/udiskie \
    .config/9menu \
    .config/nvim \
    .config/starship.toml \
    .config/mise/config.toml \
    .config/rafex/theme \
    .config/rafex/themes \
    .config/rafex/runtime-java-selection \
    .local/bin \
    .tmux \
    .local/share/java-runtimes \
    .local/share/node-runtimes \
    .local/share/build-runtimes \
    .local/share/graalvm-runtimes \
    .local/share/rafex-runtimes; do
    copy_user_path "$HOME/$path" "$path"
  done
  record_exclusion "EXCLUIDO: $HOME/.local/share/mise/installs (instalación interna de mise; se conserva solo el inventario)"
  record_exclusion "EXCLUIDO: $HOME/.cache y logs privados"
  record_exclusion "EXCLUIDO: $HOME/.config/dconf y $HOME/.config/pulse/cookie"
  record_exclusion "EXCLUIDO: $HOME/.ssh, credenciales Git, Wi-Fi, keyrings y tokens"
}

copy_system_files() {
  copy_system_path /etc/fstab fstab.reference
  copy_system_path /etc/crypttab crypttab.reference
  copy_system_path /etc/default/grub grub.reference
  copy_system_path /etc/tlp.d/90-rafex-battery.conf tlp/90-rafex-battery.conf
  copy_system_path /etc/NetworkManager/NetworkManager.conf networkmanager/NetworkManager.conf
  copy_system_path /etc/NetworkManager/conf.d/90-rafex-managed.conf networkmanager/90-rafex-managed.conf

  local file
  for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources /etc/apt/keyrings/*; do
    [[ -e "$file" ]] || continue
    case "$file" in
      */auth.conf|*/auth.conf.d/*) record_exclusion "EXCLUIDO (sensible): $file" ;;
      *) copy_system_path "$file" "apt-reference/${file#/etc/apt/}" ;;
    esac
  done
}

# shellcheck disable=SC2016
write_inventories() {
  write_inventory os.txt sh -c 'cat /etc/os-release; uname -a; uptime'
  write_inventory hardware-pci.txt lspci -nnk
  write_inventory hardware-usb.txt sh -c 'lsusb; echo; lsusb -t'
  write_inventory hardware-block.txt lsblk -e7 -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,TYPE,MOUNTPOINTS,TRAN,RM
  write_inventory mounts.txt findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS
  write_inventory groups.txt id
  write_inventory services-system.txt systemctl list-unit-files --type=service --no-pager
  write_inventory services-user.txt systemctl --user list-unit-files --state=enabled --no-pager
  write_inventory apt-installed.txt sh -c 'dpkg-query -W -f="${binary:Package}\t${Version}\t${db:Status-Status}\n"'
  write_inventory apt-manual.txt apt-mark showmanual
  write_inventory network-status.txt nmcli device status
  write_inventory graphics.txt sh -c 'ls -l /dev/dri 2>/dev/null; vainfo --display drm --device /dev/dri/renderD128 2>/dev/null; glxinfo -B 2>/dev/null; vulkaninfo --summary 2>/dev/null; ffmpeg -hwaccels 2>/dev/null'
  write_inventory audio-video-input.txt sh -c 'aplay -l 2>/dev/null; wpctl status 2>/dev/null; v4l2-ctl --list-devices 2>/dev/null; xsetwacom --list devices 2>/dev/null'
  write_inventory power.txt sh -c 'cat /sys/power/mem_sleep 2>/dev/null; for f in /sys/class/power_supply/BAT*/*; do [ -r "$f" ] && printf "%s=" "$f" && cat "$f"; done; systemctl status fstrim.timer --no-pager 2>/dev/null'
  write_inventory runtimes.txt sh -c 'find "$HOME/.local/share" -maxdepth 4 \( -path "*/java-runtimes/*" -o -path "*/node-runtimes/*" -o -path "*/build-runtimes/*" -o -path "*/graalvm-runtimes/*" -o -path "*/rafex-runtimes/*" \) -printf "%y %p\n" 2>/dev/null; mise ls --installed 2>/dev/null || true'
  write_inventory repo-state.txt sh -c 'git -C "$1" status --short --branch; git -C "$1" log -5 --oneline' sh "$REPO_ROOT"

  write_privileged_inventory ufw.txt ufw status verbose
  write_privileged_inventory sshd-effective.txt sshd -T
  write_privileged_inventory tlp.txt tlp-stat -s
  write_privileged_inventory apparmor.txt aa-status
  write_privileged_inventory audit.txt auditctl -s
  write_privileged_inventory usbguard.txt usbguard list-devices
  write_privileged_inventory sockets.txt ss -lntup
}

write_migration_report() {
  cat > "$STAGE/MIGRATION_REPORT.md" <<EOF
# Informe de migración ThinkPad

Generado: $(date --iso-8601=seconds 2>/dev/null || date)

## Fuente normativa

La configuración curada procede de:

\`dotfiles/profiles/thinkpad-x1-yoga-1st/\`

La MacBook no se consultó ni se copió. El repositorio es la fuente seleccionada
para evitar transferir configuraciones específicas de macOS o hardware antiguo.

## Clasificación

| Elemento | Decisión | Motivo |
|---|---|---|
| i3, i3status, Rofi, Dunst, Picom, Alacritty, 9menu | Reemplazar por perfil | Configuración portable y versionada |
| tmux | Combinar/regenerar | La copia actual contiene bloques duplicados |
| Bash | Combinar manualmente | Contiene bloques administrados y preferencias locales |
| udiskie | Regenerar después de instalar | Falta el ejecutable en la instalación actual |
| Xorg, DPI y autorandr | Regenerar para ThinkPad | Dependen de salidas y hardware reales |
| NetworkManager | Conservar/reconciliar | No copiar perfiles ni secretos Wi-Fi |
| fstab, crypttab y GRUB | Solo referencia | Contienen UUID y rutas de esta instalación |
| runtimes internos de mise | No restaurar | Los instaladores propios gobiernan las descargas |
| secretos, claves, cookies y credenciales | Excluir | No deben viajar en el respaldo portable |

## Hallazgos actuales

- El NVMe usa LUKS + LVM; root está cifrado.
- GPU Intel usa i915 y tiene VA-API disponible.
- Audio usa PipeWire/WirePlumber.
- Cámara, Wacom, sensores, Wi-Fi, Bluetooth, WWAN y NVMe están detectados.
- UFW, TLP, TRIM, NetworkManager y AppArmor están activos.
- Faltan o requieren revisión fail2ban, auditd, usbguard, unattended-upgrades,
  udiskie y Podman.
- Temurin 25 está instalado manualmente e integrado en mise.

Los inventarios detallados están en \`metadata/\`; este informe no contiene
secretos ni perfiles de conexión.
EOF
}

write_readme() {
  cat > "$STAGE/README.md" <<EOF
# Respaldo ThinkPad

Este directorio contiene una instantánea no destructiva del estado de la
ThinkPad y una copia curada del perfil versionado.

## Restauración

Revisar primero \`MIGRATION_REPORT.md\`. No restaurar automáticamente:

- \`system/fstab.reference\`
- \`system/crypttab.reference\`
- \`system/grub.reference\`
- fuentes APT ni configuraciones de NetworkManager

Instalar el repositorio y ejecutar el perfil ThinkPad antes de combinar archivos
locales. Los secretos fueron excluidos intencionalmente.

## Verificación

Desde este directorio:

\`\`\`sh
sha256sum -c manifest.sha256
\`\`\`

El archivo comprimido hermano \`$(basename "$FINAL_ARCHIVE")\` contiene esta
misma estructura.
EOF
}

verify_no_secrets() {
  local matches
  matches="$(grep -RIlE --exclude='manifest.sha256' --exclude='EXCLUSIONS.md' \
    'BEGIN[[:space:]].*PRIVATE KEY|AWS_SECRET_ACCESS_KEY|GH_TOKEN|PASSWORD[[:space:]]*=|TOKEN[[:space:]]*=|API_KEY[[:space:]]*=' \
    "$STAGE" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    fatal "se detectaron posibles secretos en el staging; no se publicará el respaldo"
  fi
}

write_manifest() {
  (cd "$STAGE" && find . -type f ! -name manifest.sha256 -print0 | sort -z | while IFS= read -r -d '' file; do sha256sum -- "$file"; done) > "$STAGE/manifest.sha256"
}

cleanup() {
  if [[ -n "$STAGE" && -d "$STAGE" ]]; then
    rm -rf -- "$STAGE"
  fi
}

create_backup() {
  local basename final_tmp archive_tmp
  sudo -v
  validate_destination || fatal "monta primero el SSD externo con etiqueta $EXPECTED_LABEL"

  basename="rafex-thinkpad-recovery-$STAMP"
  FINAL_DIR="$DESTINATION_BASE/$basename"
  FINAL_ARCHIVE="$DESTINATION_BASE/$basename.tar.gz"
  [[ ! -e "$FINAL_DIR" && ! -e "$FINAL_ARCHIVE" ]] || fatal "ya existe un respaldo con el nombre $basename"

  STAGE="$(mktemp -d "$DESTINATION_BASE/.${basename}.staging.XXXXXX")"
  trap cleanup EXIT
  mkdir -p "$STAGE"/{metadata,user,system,curated-profile}
  printf '# Exclusiones del respaldo\n\n' > "$STAGE/EXCLUSIONS.md"

  info "copiando configuraciones de usuario"
  copy_user_files
  info "copiando configuración de sistema como referencia"
  copy_system_files
  info "generando inventarios"
  write_inventories
  info "copiando perfil curado ThinkPad"
  copy_portable_tree "$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st" "$STAGE/curated-profile/"
  write_migration_report
  write_readme
  verify_no_secrets
  write_manifest

  final_tmp="$DESTINATION_BASE/.${basename}.final.XXXXXX"
  final_tmp="$(mktemp -d "$final_tmp")"
  copy_portable_tree "$STAGE/." "$final_tmp/"
  mv -- "$final_tmp" "$FINAL_DIR"
  STAGE=""

  archive_tmp="$DESTINATION_BASE/.${basename}.tar.gz.XXXXXX"
  archive_tmp="$(mktemp "$archive_tmp")"
  rm -f -- "$archive_tmp"
  tar -czf "$archive_tmp" -C "$DESTINATION_BASE" "$basename"
  mv -- "$archive_tmp" "$FINAL_ARCHIVE"

  (cd "$FINAL_DIR" && sha256sum -c manifest.sha256 >/dev/null)
  tar -tzf "$FINAL_ARCHIVE" >/dev/null
  success "respaldo creado: $FINAL_DIR"
  success "archivo creado: $FINAL_ARCHIVE"
  success "manifest.sha256 y extracción del archivo verificados"
}

main() {
  parse_args "$@"
  require_commands
  printf '%b═══ Respaldo ThinkPad ═══%b\n' "${BOLD}${CYAN}" "$RESET"
  printf 'modo=%s\n' "$MODE"
  printf 'destino=%s\n' "$DESTINATION_BASE"
  printf 'perfil=%s\n' "$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"

  if [[ "$MODE" == "check" ]]; then
    validate_destination || true
    show_plan
    success "check terminado; no se modificó el sistema ni se crearon archivos"
  elif [[ "$MODE" == "plan" ]]; then
    validate_destination || warn "el plan puede revisarse antes de montar el SSD"
    show_plan
    success "plan terminado; no se modificó el sistema"
  else
    create_backup
  fi
}

main "$@"
