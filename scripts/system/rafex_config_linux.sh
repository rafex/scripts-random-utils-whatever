#!/usr/bin/env bash
# rafex_config_linux.sh v2.0.0
# Replica configuración y conserva el estado instalado en un historial local.
set -Eeuo pipefail
umask 077
export LC_ALL=C

ACTION=status
COMPONENT=all
ALLOW_ADOPT=0
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PROFILE="dotfiles/profiles/thinkpad-x1-yoga-1st"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
HISTORY_ROOT="$DATA_HOME/rafex-thinkpad"
SNAPSHOT_ROOT="$HISTORY_ROOT/snapshots"
ACTIVE_LINK="$HISTORY_ROOT/active"
STATE_DIR="$STATE_HOME/rafex/config-publisher"
BACKUP_ROOT="$STATE_DIR/backups/$STAMP"
LOG_FILE="$STATE_DIR/changes.jsonl"
LOCK_FILE="$STATE_DIR/deploy.lock"
MANIFEST_REL="$PROFILE/thinkpad-state-manifest.tsv"

export RAFEX_PUBLISH_CHECKOUT="$REPO_ROOT"
export RAFEX_PUBLISH_GENERATED_ROOT="$STATE_HOME/rafex/config-generated/thinkpad"
export RAFEX_PUBLISH_STATE_DIR="$STATE_DIR"
export RAFEX_PUBLISH_LOG="$LOG_FILE"
export RAFEX_PUBLISH_LOCK_FILE="$LOCK_FILE"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/rafex_config_publish_linux.sh"

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso:
  rafex_config_linux.sh --check
  rafex_config_linux.sh --status
  rafex_config_linux.sh --sync
  rafex_config_linux.sh --snapshot
  rafex_config_linux.sh --plan [--component all|i3|visual|hardware|network|lab]
  rafex_config_linux.sh --adopt [--component ...]
  rafex_config_linux.sh --deploy [--component ...]
  rafex_config_linux.sh --rollback --component i3|visual|hardware|network|lab
  rafex_config_linux.sh --doctor

El checkout principal replica y ejecuta. El historial operativo vive en
~/.local/share/rafex-thinkpad y recibe commits locales, nunca push automático.
EOF
}

parse_args() {
  local selected=0
  while (($#)); do
    case "$1" in
      --check|--status|--sync|--snapshot|--plan|--adopt|--deploy|--rollback|--doctor)
        (( selected == 0 )) || die 'selecciona una sola acción'
        ACTION="${1#--}"; selected=1; shift ;;
      --component)
        (($# > 1)) || die '--component requiere un valor'
        COMPONENT="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este publicador requiere Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal, no como root'
  local command_name
  for command_name in awk cmp cp date find git install ln mktemp mv realpath sha256sum stat; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
}

require_lock() {
  command -v flock >/dev/null 2>&1 || die 'falta flock de util-linux'
  mkdir -p -- "$STATE_DIR"
  chmod 700 -- "$STATE_DIR"
  exec 9>"$LOCK_FILE"
  flock -n 9 || die 'ya existe otra operación Rafex en curso'
}

validate_component() {
  case "$COMPONENT" in
    all|i3|visual|hardware|network|lab|session) ;;
    *) die "componente inválido: $COMPONENT" ;;
  esac
}

component_matches() {
  local actual="$1"
  case "$COMPONENT:$actual" in
    all:*|i3:session|i3:i3|visual:visual|hardware:hardware|hardware:system|network:network|lab:lab|session:session) return 0 ;;
    *) return 1 ;;
  esac
}

repo_path() { printf '%s/%s\n' "$REPO_ROOT" "$1"; }
live_path() {
  case "$1" in
    .config/*) printf '%s/%s\n' "$CONFIG_HOME" "${1#.config/}" ;;
    .local/bin/*) printf '%s/%s\n' "$HOME" "$1" ;;
    /*) printf '%s\n' "$1" ;;
    *) die "destino no permitido: $1" ;
  esac
}

manifest_file() { repo_path "$MANIFEST_REL"; }

history_init() {
  local generated_gitignore=0
  mkdir -p -- "$HISTORY_ROOT" "$SNAPSHOT_ROOT" "$STATE_DIR"
  chmod 700 -- "$HISTORY_ROOT" "$SNAPSHOT_ROOT" "$STATE_DIR"
  if [[ ! -d "$HISTORY_ROOT/.git" ]]; then git -C "$HISTORY_ROOT" init -q; fi
  # Siempre fija identidad local, incluso si .git fue creado anteriormente.
  git -C "$HISTORY_ROOT" config --local user.name 'Rafex ThinkPad'
  git -C "$HISTORY_ROOT" config --local user.email 'rafex-thinkpad@localhost'
  if [[ ! -f "$HISTORY_ROOT/.gitignore" ]]; then
    printf '%s\n' '*.tmp' '*.bak' '*.swp' '.history.lock' '.snapshot-*' > "$HISTORY_ROOT/.gitignore"
    chmod 600 -- "$HISTORY_ROOT/.gitignore"
    generated_gitignore=1
  fi
  if ! git -C "$HISTORY_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$HISTORY_ROOT" add -- .gitignore
    git -C "$HISTORY_ROOT" commit -q -m 'init: ThinkPad installed history'
  elif (( generated_gitignore )); then
    git -C "$HISTORY_ROOT" add -- .gitignore
    git -C "$HISTORY_ROOT" commit -q -m 'chore: initialize ThinkPad history metadata'
  fi
}

history_clean() {
  [[ ! -d "$HISTORY_ROOT/.git" ]] || [[ -z "$(git -C "$HISTORY_ROOT" status --porcelain --untracked-files=all)" ]]
}

history_identity_ok() {
  [[ ! -d "$HISTORY_ROOT/.git" ]] && return 0
  [[ "$(git -C "$HISTORY_ROOT" config --local --get user.name 2>/dev/null || true)" == 'Rafex ThinkPad' ]] || return 1
  [[ "$(git -C "$HISTORY_ROOT" config --local --get user.email 2>/dev/null || true)" == 'rafex-thinkpad@localhost' ]]
}

sync_source() {
  [[ -d "$REPO_ROOT/.git" ]] || die 'no existe el checkout ejecutor'
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]] ||
    die 'checkout ejecutor con cambios sin registrar'
  git -C "$REPO_ROOT" pull --ff-only
  ok "checkout replicador sincronizado: $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
}

source_clean() {
  [[ -d "$REPO_ROOT/.git" ]] || return 1
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]]
}

validate_manifest() {
  local component resource kind source target strategy mode validator risk
  [[ -f "$(manifest_file)" ]] || die "falta manifiesto: $(manifest_file)"
  awk -F'|' '
    /^#/ || NF == 0 { next }
    NF != 10 { print "línea con 10 campos requeridos: " NR; bad=1 }
    { resource[$2]++; target[$5]++ }
    END {
      for (key in resource) if (resource[key] > 1) { print "recurso duplicado: " key; bad=1 }
      for (key in target) if (target[key] > 1) { print "destino duplicado: " key; bad=1 }
      exit bad
    }
  ' "$(manifest_file)" || die 'manifiesto con propietarios o destinos duplicados'
  while IFS='|' read -r component resource kind source target strategy mode validator _exclusions risk; do
    [[ -z "$component" || "$component" == \#* ]] && continue
    [[ "$component" =~ ^[a-z0-9._-]+$ && "$resource" =~ ^[a-z0-9._-]+$ ]] || die "identificador inválido: $component/$resource"
    [[ "$kind" == user || "$kind" == system ]] || die "tipo inválido: $kind"
    [[ "$strategy" == symlink || "$strategy" == copy ]] || die "estrategia inválida: $strategy"
    [[ "$mode" =~ ^0[0-7]{3}$ ]] || die "modo inválido: $mode"
    [[ "$target" != *..* ]] || die "destino inseguro: $target"
    if [[ "$kind" == user ]]; then
      [[ "$target" == .config/* || "$target" == .local/bin/* ]] || die "destino de usuario inválido: $target"
      [[ "$source" != /* && "$source" != *..* ]] || die "fuente insegura: $source"
      [[ -f "$(repo_path "$source")" ]] || die "fuente del manifiesto ausente: $(repo_path "$source")"
      rafex_publish_assert_inside "$(realpath -m -- "$(repo_path "$source")")" "$REPO_ROOT" ||
        die "fuente fuera del checkout: $source"
    else
      [[ "$target" == /* ]] || die "destino de sistema inválido: $target"
      [[ "$source" == - ]] || die 'las fuentes de /etc deben provenir del snapshot'
    fi
  done < "$(manifest_file)"
}

log_change() {
  local event="$1" resource="$2" target="$3" before="$4" after="$5"
  mkdir -p -- "$STATE_DIR"
  printf '{"timestamp":"%s","event":"%s","resource":"%s","target":"%s","before":"%s","after":"%s","component":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$resource" "$target" "$before" "$after" "$COMPONENT" >> "$LOG_FILE"
  chmod 600 -- "$LOG_FILE"
}

sha256() {
  if [[ -L "$1" ]]; then printf 'symlink:%s\n' "$(readlink -- "$1")"
  elif [[ -f "$1" ]]; then sha256sum -- "$1" | awk '{print $1}'
  else printf 'absent\n'; fi
}

snapshot_dest() {
  local stage="$1" kind="$2" target="$3"
  if [[ "$kind" == user ]]; then printf '%s/home/%s\n' "$stage" "$target"
  else printf '%s/system%s\n' "$stage" "$target"; fi
}

copy_snapshot_file() {
  local source="$1" destination="$2" mode="$3"
  [[ -f "$source" ]] || die "archivo instalado ausente o ilegible: $source"
  mkdir -p -- "$(dirname -- "$destination")"
  cp -L -- "$source" "$destination"
  chmod "$mode" -- "$destination"
}

repo_source() {
  local source="$1" resource="$2" theme='nord'
  if [[ "$resource" == eww.scss && -r "$CONFIG_HOME/rafex/theme" ]]; then
    theme="$(head -n 1 "$CONFIG_HOME/rafex/theme")"
    [[ "$theme" =~ ^(paper|nord|everforest|dracula)$ ]] || theme=nord
    source="$PROFILE/config/rafex/themes/$theme/eww.scss"
  fi
  repo_path "$source"
}

active_snapshot() {
  [[ -L "$ACTIVE_LINK" ]] || return 1
  local resolved
  resolved="$(readlink -f -- "$ACTIVE_LINK")"
  rafex_publish_assert_inside "$resolved" "$SNAPSHOT_ROOT" || return 1
  [[ "$resolved" == "$SNAPSHOT_ROOT"/* && -d "$resolved" ]] || return 1
  printf '%s\n' "$resolved"
}

seed_stage_from_live() {
  local stage="$1" allow_repo_fallback="${2:-0}" component resource kind source target strategy mode validator risk destination live_source
  while IFS='|' read -r component resource kind source target strategy mode validator _exclusions risk; do
    [[ -z "$component" || "$component" == \#* ]] && continue
    destination="$(snapshot_dest "$stage" "$kind" "$target")"
    live_source="$(live_path "$target")"
    if [[ -e "$live_source" || -L "$live_source" ]]; then
      copy_snapshot_file "$live_source" "$destination" "$mode"
    elif (( allow_repo_fallback )) && [[ "$kind" == user ]]; then
      # En el primer deploy un helper nuevo puede aún no existir en la
      # máquina. Se usa el checkout solo como semilla; los snapshots
      # posteriores siempre capturan el archivo vivo y no lo inventan.
      copy_snapshot_file "$(repo_source "$source" "$resource")" "$destination" "$mode"
    else
      die "archivo instalado ausente o ilegible: $live_source"
    fi
  done < "$(manifest_file)"
}

seed_stage_from_active_or_live() {
  local stage="$1" active
  if active="$(active_snapshot 2>/dev/null)"; then
    cp -a -- "$active/home" "$stage/"
    cp -a -- "$active/system" "$stage/"
  else
    seed_stage_from_live "$stage" 1
  fi
}

overlay_repo_files() {
  local stage="$1" component resource kind source target strategy mode validator risk destination
  while IFS='|' read -r component resource kind source target strategy mode validator _exclusions risk; do
    [[ -z "$component" || "$component" == \#* ]] && continue
    component_matches "$component" || continue
    [[ "$kind" == user ]] || continue
    # El checkout es la fuente de los archivos estáticos. Los archivos de
    # estrategia copy son estado operativo (tema, barra activa, Dunst, etc.)
    # y deben conservarse desde active/live para no revertirlos con valores
    # obsoletos al desplegar otra tanda del replicador.
    [[ "$strategy" == symlink ]] || continue
    destination="$(snapshot_dest "$stage" "$kind" "$target")"
    copy_snapshot_file "$(repo_source "$source" "$resource")" "$destination" "$mode"
  done < "$(manifest_file)"
}

commit_history() {
  local revision="$1"
  printf '%s\n' "$revision" > "$HISTORY_ROOT/source-revision"
  chmod 600 -- "$HISTORY_ROOT/source-revision"
  git -C "$HISTORY_ROOT" add --all
  if ! git -C "$HISTORY_ROOT" diff --cached --quiet; then git -C "$HISTORY_ROOT" commit -q -m "snapshot: source $revision"; fi
}

activate_snapshot() {
  local stage="$1" stamp="$2" final temporary
  final="$SNAPSHOT_ROOT/$stamp"
  temporary="$HISTORY_ROOT/.active.$stamp"
  mv -f -- "$stage" "$final"
  ln -s -- "snapshots/$stamp" "$temporary"
  mv -Tf -- "$temporary" "$ACTIVE_LINK"
  printf '%s\n' "$final"
}

create_snapshot() {
  local mode="$1" stage stamp final revision
  history_init
  history_clean || die 'el historial local tiene cambios fuera del publicador'
  stamp="${STAMP}_$RANDOM"
  stage="$HISTORY_ROOT/.snapshot-$stamp"
  mkdir -p -- "$stage/home" "$stage/system" "$stage/metadata"
  if [[ "$mode" == live ]]; then seed_stage_from_live "$stage"; else seed_stage_from_active_or_live "$stage"; overlay_repo_files "$stage"; fi
  revision="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  {
    printf 'component|resource|kind|target|sha256|mode|validator|risk\n'
    local component resource kind source target strategy mode_field validator risk
    while IFS='|' read -r component resource kind source target strategy mode_field validator _exclusions risk; do
      [[ -z "$component" || "$component" == \#* ]] && continue
      printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$component" "$resource" "$kind" "$target" \
        "$(sha256 "$(snapshot_dest "$stage" "$kind" "$target")")" "$mode_field" "$validator" "$risk"
    done < "$(manifest_file)"
  } > "$stage/metadata/manifest.tsv"
  printf 'source_revision=%s\ncreated_utc=%s\nmode=%s\n' "$revision" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" > "$stage/metadata/state.txt"
  chmod 600 -- "$stage/metadata/manifest.tsv" "$stage/metadata/state.txt"
  final="$(activate_snapshot "$stage" "$stamp")"
  cp -p -- "$final/metadata/manifest.tsv" "$HISTORY_ROOT/manifest.tsv"
  chmod 600 -- "$HISTORY_ROOT/manifest.tsv"
  commit_history "$revision"
  ok "snapshot activo: $final"
}

backup_target() {
  local component="$1" resource="$2" kind="$3" target="$4" backup_target existed=0
  mkdir -p -- "$BACKUP_ROOT/$component"
  backup_target="$BACKUP_ROOT/$component/${resource//\//_}"
  if [[ "$kind" == user ]]; then
    if [[ -e "$target" || -L "$target" ]]; then existed=1; cp -a -- "$target" "$backup_target"; fi
  elif sudo -n test -e "$target" 2>/dev/null; then
    existed=1
    sudo -n cp -a -- "$target" "$backup_target"
    sudo -n chown -R "$(id -u):$(id -g)" -- "$backup_target"
  fi
  printf '%s|%s|%s|%s|%s|%s\n' "$component" "$resource" "$kind" "$target" "$backup_target" "$existed" >> "$BACKUP_ROOT/manifest.tsv"
}

publish_user() {
  local source="$1" target="$2" mode="$3" before temporary
  [[ -f "$source" ]] || die "fuente del snapshot ausente: $source"
  if [[ -L "$target" && "$(readlink -f -- "$target")" == "$(realpath -m -- "$source")" ]]; then return 0; fi
  if [[ -e "$target" || -L "$target" ]] && (( ! ALLOW_ADOPT )); then die "destino de usuario no administrado; ejecuta --adopt tras revisar: $target"; fi
  before="$(sha256 "$target")"
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-link.XXXXXX")"
  rm -f -- "$temporary"
  ln -s -- "$source" "$temporary"
  mv -Tf -- "$temporary" "$target"
  chmod "$mode" -- "$source"
  log_change published "${target#"$HOME"/}" "$target" "$before" "$(sha256 "$target")"
}

publish_user_copy() {
  local source="$1" target="$2" mode="$3" before temporary
  [[ -f "$source" ]] || die "fuente del snapshot ausente: $source"
  if [[ -e "$target" || -L "$target" ]] && (( ! ALLOW_ADOPT )); then
    cmp -s -- "$source" "$target" || die "destino dinámico no administrado; ejecuta --adopt tras revisar: $target"
  fi
  before="$(sha256 "$target")"
  mkdir -p -- "$(dirname -- "$target")"
  temporary="$(mktemp "$(dirname -- "$target")/.rafex-copy.XXXXXX")"
  cp -L -- "$source" "$temporary"
  chmod "$mode" -- "$temporary"
  mv -f -- "$temporary" "$target"
  log_change published "${target#"$HOME"/}" "$target" "$before" "$(sha256 "$target")"
}

publish_system() {
  local source="$1" target="$2" mode="$3" temporary
  sudo -n test -r "$source" || die "sudo -n no puede leer el snapshot para $target"
  temporary="$target.rafex.$STAMP"
  sudo -n install -D -m "$mode" -- "$source" "$temporary"
  sudo -n mv -f -- "$temporary" "$target"
  sudo -n chown root:root -- "$target"
}

publish_snapshot() {
  local active component resource kind source target strategy mode validator risk live active_file
  active="$(active_snapshot)" || die 'no existe snapshot activo; ejecuta --snapshot o --adopt'
  mkdir -p -- "$BACKUP_ROOT"
  chmod 700 -- "$BACKUP_ROOT"
  : > "$BACKUP_ROOT/manifest.tsv"
  chmod 600 -- "$BACKUP_ROOT/manifest.tsv"
  while IFS='|' read -r component resource kind source target strategy mode validator _exclusions risk; do
    [[ -z "$component" || "$component" == \#* ]] && continue
    component_matches "$component" || continue
    live="$(live_path "$target")"
    backup_target "$component" "$resource" "$kind" "$live"
    if [[ "$kind" == user ]]; then
      active_file="$active/home/$target"
      if [[ "$strategy" == symlink ]]; then publish_user "$active_file" "$live" "$mode"; else publish_user_copy "$active_file" "$live" "$mode"; fi
    else
      active_file="$active/system$target"
      [[ -f "$active_file" ]] || die "archivo de sistema ausente en snapshot: $active_file"
      publish_system "$active_file" "$target" "$mode"
    fi
  done < "$(manifest_file)"
  printf '%s\n' "$BACKUP_ROOT" > "$STATE_DIR/last-backup"
  chmod 600 -- "$STATE_DIR/last-backup"
  ok "publicación $COMPONENT completada; respaldo: $BACKUP_ROOT"
}

show_status() {
  local component resource kind source target strategy mode validator risk live
  printf 'source=%s\n' "$REPO_ROOT"
  printf 'history=%s\n' "$HISTORY_ROOT"
  printf 'active=%s\n' "$(active_snapshot 2>/dev/null || printf none)"
  if [[ -d "$HISTORY_ROOT/.git" ]]; then
    printf 'history-revision=%s\n' "$(git -C "$HISTORY_ROOT" rev-parse --short HEAD 2>/dev/null || printf none)"
    history_clean && printf 'history-clean=yes\n' || printf 'history-clean=no\n'
  else printf 'history=not-initialized\n'; fi
  while IFS='|' read -r component resource kind source target strategy mode validator _exclusions risk; do
    [[ -z "$component" || "$component" == \#* ]] && continue
    live="$(live_path "$target")"
    if [[ "$kind" == user && "$strategy" == symlink && -L "$live" ]]; then printf '%s=symlink\n' "$resource"; elif [[ -e "$live" ]]; then printf '%s=copy-or-manual\n' "$resource"; else printf '%s=missing\n' "$resource"; fi
  done < "$(manifest_file)"
  [[ -f "$STATE_DIR/last-backup" ]] && printf 'last-backup=%s\n' "$(<"$STATE_DIR/last-backup")" || printf 'last-backup=none\n'
}

show_plan() {
  printf '═══ Plan Rafex ThinkPad (%s) ═══\n' "$COMPONENT"
  printf 'checkout replicador: %s\nhistorial operativo: %s\n' "$REPO_ROOT" "$HISTORY_ROOT"
  printf '%s\n' '1. sincronizar checkout con git pull --ff-only (solo deploy/adopt)'
  printf '%s\n' '2. generar snapshot validado bajo snapshots/<fecha> y activar active atómicamente'
  printf '%s\n' '3. publicar symlinks de usuario hacia active/home/'
  printf '%s\n' '4. publicar /etc con install + mv atómico, root:root y modo del manifiesto'
  printf '%s\n' '5. crear commit local del historial; nunca git push'
  printf '%s\n' 'No se modifican BIOS, bootloader, particiones, teléfonos ni red destructiva.'
}

doctor() {
  local failures=0 active component resource kind source target strategy mode validator risk live expected owner mode_live
  active="$(active_snapshot 2>/dev/null || true)"
  [[ -n "$active" ]] || { warn 'no existe active apuntando a un snapshot'; failures=$((failures + 1)); }
  while IFS='|' read -r component resource kind source target strategy mode validator _exclusions risk; do
    [[ -z "$component" || "$component" == \#* ]] && continue
    live="$(live_path "$target")"
    if [[ "$kind" == user && "$strategy" == symlink ]]; then
      expected="$active/home/$target"
      if [[ -L "$live" && -n "$active" && "$(readlink -f -- "$live")" == "$(realpath -m -- "$expected")" ]]; then ok "$resource: symlink administrado"; else warn "$resource: destino manual, roto o fuera de active"; failures=$((failures + 1)); fi
    elif [[ "$kind" == user && "$strategy" == copy && -f "$live" && ! -L "$live" ]]; then
      ok "$resource: archivo dinámico presente"
    elif [[ -e "$live" ]]; then
      owner="$(stat -c '%U:%G' -- "$live" 2>/dev/null || printf unknown)"
      mode_live="$(stat -c '%a' -- "$live" 2>/dev/null || printf unknown)"
      if [[ "$owner" == root:root && "$mode_live" == "${mode#0}" ]]; then
        ok "$resource: root:root $mode_live"
      else
        warn "$resource: propietario/modo divergente ($owner $mode_live)"
        failures=$((failures + 1))
      fi
    else warn "$resource: ausente"; failures=$((failures + 1)); fi
  done < "$(manifest_file)"
  if [[ -f "$CONFIG_HOME/i3/config" ]] && command -v i3 >/dev/null 2>&1; then
    if i3 -C -c "$CONFIG_HOME/i3/config" >/dev/null 2>&1; then
      ok 'i3: sintaxis válida'
    else
      warn 'i3: sintaxis inválida'
      failures=$((failures + 1))
    fi
  fi
  (( failures == 0 )) || return 1
  ok 'doctor: sin conflictos de publicación'
}

rollback() {
  local root component resource kind target backup existed
  [[ "$COMPONENT" != all ]] || die '--rollback requiere --component'
  [[ -f "$STATE_DIR/last-backup" ]] || die 'no existe respaldo para rollback'
  root="$(<"$STATE_DIR/last-backup")"
  [[ -f "$root/manifest.tsv" ]] || die "manifiesto de respaldo ausente: $root"
  while IFS='|' read -r component resource kind target backup existed; do
    [[ "$component" == "$COMPONENT" || "$COMPONENT" == i3 && "$component" == session || "$COMPONENT" == hardware && "$component" == system ]] || continue
    if [[ "$existed" == 1 ]]; then
      if [[ "$kind" == user ]]; then rm -f -- "$target"; mkdir -p -- "$(dirname -- "$target")"; cp -a -- "$backup" "$target"
      else
        sudo -n install -D -m 0644 -- "$backup" "$target.rafex-rollback"
        sudo -n mv -f -- "$target.rafex-rollback" "$target"
        sudo -n chown root:root -- "$target"
      fi
    else
      if [[ "$kind" == user ]]; then
        rm -f -- "$target"
      else
        sudo -n rm -f -- "$target"
      fi
    fi
    ok "rollback: $resource"
  done < "$root/manifest.tsv"
}

main() {
  parse_args "$@"
  require_linux
  validate_component
  validate_manifest
  case "$ACTION" in
    check)
      source_clean || die 'checkout replicador con cambios locales sin registrar'
      if [[ -d "$HISTORY_ROOT/.git" ]]; then
        history_identity_ok || die 'identidad Git local del historial divergente; se corregirá durante --sync/--snapshot'
        history_clean || die 'historial local con cambios sin registrar'
      fi
      ok 'manifiesto, propietarios, rutas y checkout válidos'
      ;;
    status) show_status ;;
    plan) show_plan ;;
    sync) require_lock; history_init; history_clean || die 'historial local con cambios sin registrar'; sync_source; ok 'historial local listo' ;;
    snapshot) require_lock; history_init; history_clean || die 'historial local con cambios sin registrar'; create_snapshot live ;;
    adopt) require_lock; history_init; history_clean || die 'historial local con cambios sin registrar'; sync_source; ALLOW_ADOPT=1; create_snapshot live; publish_snapshot ;;
    deploy) require_lock; history_init; history_clean || die 'historial local con cambios sin registrar'; sync_source; create_snapshot repo; publish_snapshot ;;
    doctor) doctor ;;
    rollback) require_lock; history_init; rollback ;;
  esac
}

main "$@"
