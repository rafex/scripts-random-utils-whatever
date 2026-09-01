#!/usr/bin/env bash
# v1.0.0 - Respaldos Restic cifrados e incrementales para la ThinkPad.
set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
USER_NAME="${USER:-$(id -un)}"
HOME_DIR="${HOME:?HOME debe estar definido}"
MOUNTPOINT="${RAFEX_RESTIC_MOUNTPOINT:-/run/media/$USER_NAME/ssd_rafex_1}"
BACKUP_ROOT="${RAFEX_RESTIC_BACKUP_ROOT:-$MOUNTPOINT/rafex-restic}"
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/systemd/user"
EXPECTED_LABEL="ssd_rafex_1"
SERVICE_NAME="rafex-restic-backup.service"
TIMER_NAME="rafex-restic-backup.timer"
SECRET_SERVICE="rafex-restic"

ACTION="check"
PROFILE="all"
SNAPSHOT="latest"
TARGET=""
PLAN_ONLY=0
APPLY=0
NON_INTERACTIVE=0
READ_DATA=0

KEEP_DAILY=14
KEEP_WEEKLY=8
KEEP_MONTHLY=12
KEEP_YEARLY=3

declare -a ROOTS=()
declare -a EXCLUDES=()

usage() {
  cat <<'EOF'
Uso: backup_thinkpad_restic_linux.sh [acción] [opciones]

Acciones:
  --check                         Validar sin escribir.
  --plan                          Mostrar fuentes y repositorios previstos.
  --init --profile <perfil>       Inicializar un repositorio y guardar su clave.
  --backup [--profile <perfil>]   Crear un snapshot; por defecto ambos perfiles.
  --status                        Mostrar estado sin revelar contenido.
  --verify [--read-data]          Verificar uno o ambos repositorios.
  --prune --plan|--apply          Previsualizar o aplicar retención manual.
  --restore --profile <perfil>    Restaurar a un directorio seguro.
  --install-timer                 Instalar y activar el timer de usuario.
  --uninstall-timer               Retirar el timer de usuario.

Perfiles: recovery, personal, all.
EOF
}

die() {
  printf '✗ ERROR: %s\n' "$*" >&2
  exit 1
}

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

require_user() {
  [[ "$USER_NAME" != root ]] || die 'ejecuta este script como usuario normal, no como root'
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die 'este respaldo requiere Linux'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "falta el comando: $1; ejecuta just install-restic-backup --apply"
}

require_base_commands() {
  local command_name
  for command_name in restic secret-tool findmnt lsblk mountpoint awk grep sed find mktemp \
    mkdir mv cp rm date id readlink systemctl dirname wc tr chmod cat; do
    require_command "$command_name"
  done
}

profile_valid() {
  [[ "$1" == recovery || "$1" == personal || "$1" == all ]]
}

profile_repo() {
  case "$1" in
    recovery) printf '%s/recovery' "$BACKUP_ROOT" ;;
    personal) printf '%s/personal' "$BACKUP_ROOT" ;;
    *) die "perfil inválido: $1" ;;
  esac
}

profile_secret_exists() {
  secret-tool lookup service "$SECRET_SERVICE" profile "$1" >/dev/null 2>&1
}

repo_exists() {
  [[ -f "$(profile_repo "$1")/config" ]]
}

destination_source() {
  findmnt -n -o SOURCE --target "$MOUNTPOINT" 2>/dev/null || true
}

destination_label() {
  local source
  source="$(destination_source)"
  [[ -n "$source" ]] || return 1
  lsblk -ndo LABEL "$source" 2>/dev/null | sed -n '1p'
}

destination_is_valid() {
  [[ -d "$MOUNTPOINT" ]] || return 1
  mountpoint -q "$MOUNTPOINT" || return 1
  [[ "$(destination_label)" == "$EXPECTED_LABEL" ]]
}

check_destination() {
  if destination_is_valid; then
    ok "SSD montado y etiqueta validada: $EXPECTED_LABEL"
    info "repositorios: $BACKUP_ROOT/recovery y $BACKUP_ROOT/personal"
    return 0
  fi
  warn "SSD no validado en $MOUNTPOINT; debe estar montado y tener etiqueta $EXPECTED_LABEL"
  return 1
}

require_destination() {
  destination_is_valid || die "el destino no está montado o su etiqueta no es $EXPECTED_LABEL; no se montan discos automáticamente"
  mkdir -p "$BACKUP_ROOT"
}

recovery_roots() {
  printf '%s\n' \
    "$HOME_DIR/.bashrc" \
    "$HOME_DIR/.profile" \
    "$HOME_DIR/.Xresources" \
    "$HOME_DIR/.tmux.conf" \
    "$HOME_DIR/.config/i3" \
    "$HOME_DIR/.config/i3status" \
    "$HOME_DIR/.config/alacritty" \
    "$HOME_DIR/.config/openbox" \
    "$HOME_DIR/.config/tint2" \
    "$HOME_DIR/.config/rofi" \
    "$HOME_DIR/.config/dunst" \
    "$HOME_DIR/.config/picom" \
    "$HOME_DIR/.config/udiskie" \
    "$HOME_DIR/.config/9menu" \
    "$HOME_DIR/.config/nvim" \
    "$HOME_DIR/.config/starship.toml" \
    "$HOME_DIR/.config/mise/config.toml" \
    "$HOME_DIR/.config/rafex" \
    "$HOME_DIR/.local/bin" \
    "$HOME_DIR/.local/share/rafex-runtimes" \
    "$REPO_ROOT/dotfiles/profiles/thinkpad-x1-yoga-1st"
}

personal_roots() {
  printf '%s\n' \
    "$HOME_DIR/Documents" \
    "$HOME_DIR/Projects" \
    "$HOME_DIR/Pictures" \
    "$HOME_DIR/Videos" \
    "$HOME_DIR/Music"
}

prepare_roots() {
  local selected="$1" root
  ROOTS=()
  case "$selected" in
    recovery) while IFS= read -r root; do [[ -e "$root" ]] && ROOTS+=("$root"); done < <(recovery_roots) ;;
    personal) while IFS= read -r root; do [[ -e "$root" ]] && ROOTS+=("$root"); done < <(personal_roots) ;;
    *) die "prepare_roots requiere recovery o personal" ;;
  esac
  ((${#ROOTS[@]} > 0)) || die "no hay fuentes existentes para el perfil $selected"
}

build_excludes() {
  EXCLUDES=(
    --exclude "$HOME_DIR/.ssh"
    --exclude "$HOME_DIR/.gnupg"
    --exclude "$HOME_DIR/.aws"
    --exclude "$HOME_DIR/.config/gh"
    --exclude "$HOME_DIR/.config/pulse/cookie"
    --exclude "$HOME_DIR/.local/share/keyrings"
    --exclude "$HOME_DIR/.local/share/mise/installs"
    --exclude "$HOME_DIR/.cache"
    --exclude "$HOME_DIR/.local/state"
    --exclude '*.bak.*'
    --exclude '*.swp'
    --exclude '*.nmconnection'
    --exclude '*.netrc'
    --exclude '*.npmrc'
    --exclude '*.pypirc'
    --exclude '*.git-credentials'
    --exclude '*credentials*'
    --exclude '*secret*'
    --exclude '*token*'
    --exclude 'Downloads'
  )
}

scan_recovery_for_secrets() {
  local file
  local scan_root
  local -a scan_roots=(
    "$HOME_DIR/.bashrc"
    "$HOME_DIR/.profile"
    "$HOME_DIR/.Xresources"
    "$HOME_DIR/.tmux.conf"
    "$HOME_DIR/.config/mise/config.toml"
    "$HOME_DIR/.config/rafex"
    "$HOME_DIR/.local/bin"
  )
  for scan_root in "${scan_roots[@]}"; do
    [[ -e "$scan_root" ]] || continue
    while IFS= read -r -d '' file; do
      if grep -IqE -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)[=:][^[:space:]]+|GH_TOKEN[=:][^[:space:]]+|[A-Z_]*(PASSWORD|TOKEN|SECRET|API_KEY)[A-Z_]*[=:][[:space:]]*[^[:space:]$"<>{}#][^[:space:]]{7,}' "$file"; then
        die 'se detectó un posible secreto en una configuración de recovery; se cancela antes de crear el snapshot'
      fi
    done < <(find "$scan_root" -type f -size -5M -print0 2>/dev/null)
  done
}

restic_run() {
  local profile="$1"
  shift
  RESTIC_REPOSITORY="$(profile_repo "$profile")" \
    RESTIC_PASSWORD_COMMAND="secret-tool lookup service $SECRET_SERVICE profile $profile" \
    restic "$@"
}

restic_json_snapshots() {
  local profile="$1"
  restic_run "$profile" snapshots --no-lock --json 2>/dev/null
}

repo_key_works() {
  local profile="$1"
  repo_exists "$profile" || return 1
  profile_secret_exists "$profile" || return 1
  restic_run "$profile" snapshots --no-lock --json >/dev/null 2>&1
}

profile_list() {
  if [[ "$PROFILE" == all ]]; then
    printf '%s\n' recovery personal
  else
    printf '%s\n' "$PROFILE"
  fi
}

show_roots() {
  local selected="$1" root
  prepare_roots "$selected"
  for root in "${ROOTS[@]}"; do
    printf '  %s\n' "$root"
  done
}

show_plan() {
  local selected
  printf '═══ Plan de respaldo Restic ═══\n'
  printf 'destino=%s\n' "$MOUNTPOINT"
  printf 'raíz de repositorios=%s\n' "$BACKUP_ROOT"
  printf 'retención=%sd/%sw/%sm/%sy\n' "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY" "$KEEP_YEARLY"
  while IFS= read -r selected; do
    printf 'perfil=%s repositorio=%s\n' "$selected" "$(profile_repo "$selected")"
    show_roots "$selected"
  done < <(profile_list)
  info 'exclusiones: claves, credenciales, cookies, keyrings, caches, Downloads, mise/installs y archivos .bak'
  info 'no se escribirá nada; el SSD no se montará ni reformateará'
}

show_status_profile() {
  local selected="$1" repo count last json
  repo="$(profile_repo "$selected")"
  printf 'perfil=%s\n' "$selected"
  printf '  repositorio=%s\n' "$repo"
  if repo_exists "$selected"; then
    ok "  repositorio inicializado: $selected"
  else
    warn "  repositorio no inicializado: $selected"
    return 0
  fi
  if profile_secret_exists "$selected"; then
    ok '  clave en Secret Service: sí'
  else
    warn '  clave en Secret Service: no o keyring bloqueado'
    return 0
  fi
  if json="$(restic_json_snapshots "$selected")"; then
    if command -v jq >/dev/null 2>&1; then
      count="$(printf '%s' "$json" | jq 'length')"
      last="$(printf '%s' "$json" | jq -r 'if length == 0 then "ninguno" else (sort_by(.time) | last.time) end')"
    else
      count="$(printf '%s' "$json" | grep -o '"id"' | wc -l | tr -d ' ')"
      last='instala jq para mostrar la fecha'
    fi
    info "  snapshots: $count; último: $last"
  else
    warn '  no se pudo consultar el repositorio con la clave disponible'
  fi
}

show_status() {
  local selected
  printf '═══ Estado del respaldo Restic ═══\n'
  printf 'montaje=%s\n' "$MOUNTPOINT"
  if destination_is_valid; then
    ok "SSD validado: $EXPECTED_LABEL"
  else
    warn 'SSD no montado o etiqueta no validada'
  fi
  for selected in recovery personal; do
    show_status_profile "$selected"
  done
  if [[ -f "$USER_SYSTEMD_DIR/$TIMER_NAME" ]]; then
    if systemctl --user is-enabled "$TIMER_NAME" >/dev/null 2>&1; then
      ok 'timer de usuario habilitado'
    else
      warn 'unidad del timer presente pero no habilitada'
    fi
  else
    info 'timer de usuario no instalado'
  fi
}

init_profile() {
  local selected="$1" repo password confirm
  require_destination
  require_command restic
  require_command secret-tool
  profile_valid "$selected" && [[ "$selected" != all ]] || die '--init requiere --profile recovery o personal'
  repo="$(profile_repo "$selected")"
  if [[ -e "$repo" ]]; then
    if repo_key_works "$selected"; then
      ok "repositorio ya inicializado y clave válida: $selected"
      return 0
    fi
    die "ya existe $repo pero no se pudo validar su clave; no se sobrescribirá"
  fi
  [[ -t 0 || -r /dev/tty ]] || die '--init requiere una terminal interactiva para la contraseña'
  read -r -s -p "Contraseña Restic para $selected: " password < /dev/tty
  printf '\n' >&2
  read -r -s -p 'Repita la contraseña: ' confirm < /dev/tty
  printf '\n' >&2
  [[ -n "$password" && "$password" == "$confirm" ]] || die 'las contraseñas no coinciden o están vacías'
  mkdir -p "$(dirname -- "$repo")"
  RESTIC_REPOSITORY="$repo" RESTIC_PASSWORD="$password" restic init
  if ! printf '%s' "$password" | secret-tool store --label="Rafex Restic $selected" service "$SECRET_SERVICE" profile "$selected" >/dev/null; then
    unset password confirm
    die 'el repositorio se creó, pero no se pudo guardar la clave en Secret Service; no se realizará otro init'
  fi
  unset password confirm
  ok "repositorio inicializado y clave guardada en Secret Service: $selected"
}

backup_profile() {
  local selected="$1"
  if ! destination_is_valid; then
    if (( NON_INTERACTIVE )); then
      warn "timer omitido: SSD no montado o etiqueta no validada para $selected"
      return 0
    fi
    die 'el SSD no está montado o no tiene la etiqueta esperada'
  fi
  if ! repo_key_works "$selected"; then
    if (( NON_INTERACTIVE )); then
      warn "timer omitido: repositorio o clave no disponibles para $selected"
      return 0
    fi
    die "el repositorio $selected no está inicializado o su clave no está disponible"
  fi
  prepare_roots "$selected"
  build_excludes
  [[ "$selected" != recovery ]] || scan_recovery_for_secrets
  info "creando snapshot cifrado del perfil $selected"
  restic_run "$selected" backup --one-file-system --exclude-caches --skip-if-unchanged \
    --tag "rafex-$selected" "${EXCLUDES[@]}" "${ROOTS[@]}"
  ok "snapshot creado: $selected"
}

backup_all() {
  local selected
  while IFS= read -r selected; do
    backup_profile "$selected"
  done < <(profile_list)
}

verify_profile() {
  local selected="$1"
  repo_key_works "$selected" || die "el repositorio $selected no está inicializado o su clave no está disponible"
  if (( READ_DATA )); then
    info "verificando contenido completo de $selected; puede tardar"
    restic_run "$selected" check --read-data
  else
    info "verificando estructura e integridad de $selected"
    restic_run "$selected" check
  fi
  ok "verificación correcta: $selected"
}

verify_all() {
  local selected
  while IFS= read -r selected; do
    verify_profile "$selected"
  done < <(profile_list)
}

prune_profile() {
  local selected="$1" confirmation
  require_destination
  repo_key_works "$selected" || die "el repositorio $selected no está inicializado o su clave no está disponible"
  if (( PLAN_ONLY )); then
    info "plan de retención para $selected"
    restic_run "$selected" forget --dry-run \
      --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" \
      --keep-monthly "$KEEP_MONTHLY" --keep-yearly "$KEEP_YEARLY" \
      --tag "rafex-$selected"
    return 0
  fi
  (( APPLY )) || die 'usa --prune --plan o --prune --apply'
  [[ -t 0 || -r /dev/tty ]] || die '--prune --apply requiere una terminal interactiva'
  read -r -p "Escriba PURGAR para eliminar snapshots antiguos de $selected: " confirmation < /dev/tty
  [[ "$confirmation" == PURGAR ]] || die 'poda cancelada'
  restic_run "$selected" forget \
    --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" --keep-yearly "$KEEP_YEARLY" \
    --tag "rafex-$selected" --prune
  ok "poda aplicada: $selected"
}

prune_all() {
  local selected
  while IFS= read -r selected; do
    prune_profile "$selected"
  done < <(profile_list)
}

restore_profile() {
  local selected="$1" repo_target
  profile_valid "$selected" && [[ "$selected" != all ]] || die '--restore requiere --profile recovery o personal'
  [[ -n "$TARGET" && "$TARGET" == /* ]] || die '--restore requiere un --target absoluto'
  [[ "$TARGET" != / && "$TARGET" != "$HOME_DIR" && "$TARGET" != "$HOME_DIR/"* ]] \
    || die 'por seguridad no se puede restaurar sobre / ni sobre HOME'
  [[ "$TARGET" == /tmp/* || "$TARGET" == /var/tmp/* ]] \
    || die 'por seguridad el target inicial debe estar bajo /tmp o /var/tmp'
  if [[ -e "$TARGET" && -n "$(find "$TARGET" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    die 'el directorio target no está vacío; usa un directorio temporal nuevo'
  fi
  require_destination
  repo_key_works "$selected" || die "el repositorio $selected no está inicializado o su clave no está disponible"
  mkdir -p "$TARGET"
  repo_target="$TARGET"
  info "restaurando $selected/$SNAPSHOT en $repo_target"
  restic_run "$selected" restore "$SNAPSHOT" --target "$repo_target"
  ok "restauración terminada en $repo_target; no se modificó la instalación activa"
}

backup_unit() {
  local unit_path="$1" stamp
  [[ -e "$unit_path" ]] || return 0
  stamp="$(date +%Y%m%d_%H%M%S)"
  cp -p "$unit_path" "$unit_path.bak.$stamp"
  info "respaldo de unidad creado: $unit_path.bak.$stamp"
}

install_timer() {
  local service_tmp timer_tmp
  require_command systemctl
  mkdir -p "$USER_SYSTEMD_DIR"
  backup_unit "$USER_SYSTEMD_DIR/$SERVICE_NAME"
  backup_unit "$USER_SYSTEMD_DIR/$TIMER_NAME"
  service_tmp="$(mktemp "$USER_SYSTEMD_DIR/.rafex-restic-service.XXXXXX")"
  timer_tmp="$(mktemp "$USER_SYSTEMD_DIR/.rafex-restic-timer.XXXXXX")"
  cat > "$service_tmp" <<EOF
[Unit]
Description=Respaldo Restic cifrado de Rafex
ConditionPathIsMountPoint=$MOUNTPOINT

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH --backup --profile all --non-interactive
EOF
  cat > "$timer_tmp" <<EOF
[Unit]
Description=Timer de respaldo Restic de Rafex

[Timer]
OnBootSec=15min
OnUnitActiveSec=12h
AccuracySec=15min
Persistent=false
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF
  chmod 600 "$service_tmp" "$timer_tmp"
  mv -f "$service_tmp" "$USER_SYSTEMD_DIR/$SERVICE_NAME"
  mv -f "$timer_tmp" "$USER_SYSTEMD_DIR/$TIMER_NAME"
  systemctl --user daemon-reload
  systemctl --user enable --now "$TIMER_NAME"
  ok 'timer de usuario instalado y activado; nunca ejecuta prune'
}

uninstall_timer() {
  require_command systemctl
  systemctl --user disable --now "$TIMER_NAME" >/dev/null 2>&1 || true
  rm -f "$USER_SYSTEMD_DIR/$SERVICE_NAME" "$USER_SYSTEMD_DIR/$TIMER_NAME"
  systemctl --user daemon-reload
  ok 'timer de usuario retirado; repositorios y snapshots conservados'
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run)
        PLAN_ONLY=1
        [[ "$ACTION" == check ]] && ACTION="plan"
        ;;
      --init) ACTION="init" ;;
      --backup) ACTION="backup" ;;
      --status) ACTION="status" ;;
      --verify) ACTION="verify" ;;
      --prune) ACTION="prune" ;;
      --restore) ACTION="restore" ;;
      --install-timer) ACTION="install-timer" ;;
      --uninstall-timer) ACTION="uninstall-timer" ;;
      --read-data) READ_DATA=1 ;;
      --apply) APPLY=1 ;;
      --non-interactive) NON_INTERACTIVE=1 ;;
      --profile)
        (($# >= 2)) || die '--profile requiere un valor'
        PROFILE="$2"
        shift
        ;;
      --snapshot)
        (($# >= 2)) || die '--snapshot requiere un valor'
        SNAPSHOT="$2"
        shift
        ;;
      --target)
        (($# >= 2)) || die '--target requiere un valor'
        TARGET="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción no reconocida: $1" ;;
    esac
    shift
  done
}

check_action() {
  local selected issues=0
  require_base_commands
  printf '═══ Check respaldo Restic ═══\n'
  check_destination || issues=$((issues + 1))
  profile_valid "$PROFILE" || { warn "perfil inválido: $PROFILE"; issues=$((issues + 1)); }
  while IFS= read -r selected; do
    if repo_exists "$selected"; then ok "repositorio presente: $selected"; else warn "repositorio ausente: $selected"; fi
    if profile_secret_exists "$selected"; then ok "clave disponible en Secret Service: $selected"; else warn "clave ausente o keyring bloqueado: $selected"; fi
  done < <(profile_list)
  (( issues == 0 )) || return 1
  ok 'check completado sin escrituras'
}

main() {
  parse_args "$@"
  require_user
  require_linux
  case "$ACTION" in
    check) check_action ;;
    plan)
      require_base_commands
      show_plan
      ;;
    init) require_base_commands; init_profile "$PROFILE" ;;
    backup) require_base_commands; backup_all ;;
    status) require_base_commands; show_status ;;
    verify) require_base_commands; verify_all ;;
    prune) require_base_commands; prune_all ;;
    restore) require_base_commands; restore_profile "$PROFILE" ;;
    install-timer) require_base_commands; install_timer ;;
    uninstall-timer) require_base_commands; uninstall_timer ;;
    *) die "acción inválida: $ACTION" ;;
  esac
}

main "$@"
