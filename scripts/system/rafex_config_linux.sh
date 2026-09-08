#!/usr/bin/env bash
# rafex_config_linux.sh v1.1.1
# Replica de forma híbrida la configuración ThinkPad y conserva el estado
# instalado en un repositorio local separado del checkout ejecutor.
set -Eeuo pipefail
umask 077
export LC_ALL=C

ACTION=status
STAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
HISTORY_ROOT="$DATA_HOME/rafex-thinkpad"
INSTALLED_ROOT="$HISTORY_ROOT/installed"
GENERATED_ROOT="$STATE_HOME/rafex/config-generated/thinkpad"
PUBLISH_STATE_DIR="$STATE_HOME/rafex/config-publisher"
PUBLISH_LOG="$PUBLISH_STATE_DIR/publish.jsonl"
LOCK_FILE="$PUBLISH_STATE_DIR/deploy.lock"
BACKUP_ROOT=""
ALLOW_ADOPT=0

export RAFEX_PUBLISH_CHECKOUT="$INSTALLED_ROOT"
export RAFEX_PUBLISH_GENERATED_ROOT="$GENERATED_ROOT"
export RAFEX_PUBLISH_STATE_DIR="$PUBLISH_STATE_DIR"
export RAFEX_PUBLISH_LOG="$PUBLISH_LOG"
export RAFEX_PUBLISH_LOCK_FILE="$LOCK_FILE"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/rafex_config_publish_linux.sh"

PROFILE='dotfiles/profiles/thinkpad-x1-yoga-1st'
MANIFEST_REL="$PROFILE/rafex-config-manifest.tsv"
TARGET_I3="$CONFIG_HOME/i3/config"

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
  rafex_config_linux.sh --plan
  rafex_config_linux.sh --adopt
  rafex_config_linux.sh --deploy
  rafex_config_linux.sh --rollback
  rafex_config_linux.sh --doctor

`--adopt` hace la migración inicial con respaldos. `--deploy` solo publica
destinos ya administrados o ausentes; nunca reemplaza archivos manuales.
EOF
}

parse_args() {
  local chosen=0
  while (($#)); do
    case "$1" in
      --check|--status|--sync|--plan|--adopt|--deploy|--rollback|--doctor)
        (( chosen == 0 )) || die 'selecciona una sola acción'
        ACTION="${1#--}"; chosen=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  done
}

require_linux() {
  [[ "$(uname -s)" == Linux ]] || die 'este publicador requiere Linux'
  (( EUID != 0 )) || die 'ejecútalo como usuario normal, no como root'
  for command_name in awk cmp cp date git install ln mktemp mv realpath sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta la herramienta: $command_name"
  done
}

require_lock_tool() {
  command -v flock >/dev/null 2>&1 || die 'falta flock de util-linux para una operación de escritura'
}

repo_root() { printf '%s\n' "$REPO_ROOT"; }

validate_repo() {
  local root
  root="$(repo_root)"
  [[ -f "$root/$MANIFEST_REL" ]] || die "falta manifiesto: $root/$MANIFEST_REL"
  [[ -d "$root/$PROFILE/config" ]] || die "falta perfil ThinkPad: $root/$PROFILE/config"
}

history_clean() {
  if [[ ! -d "$HISTORY_ROOT/.git" ]]; then
    return 0
  fi
  if [[ -n "$(git -C "$HISTORY_ROOT" status --porcelain --untracked-files=all)" ]]; then
    warn "historial local modificado fuera del publicador: $HISTORY_ROOT"
    return 1
  fi
}

history_init() {
  local gitignore_changed=0
  mkdir -p -- "$HISTORY_ROOT" "$INSTALLED_ROOT"
  chmod 700 -- "$HISTORY_ROOT" "$INSTALLED_ROOT"
  if [[ ! -d "$HISTORY_ROOT/.git" ]]; then
    git -C "$HISTORY_ROOT" init -q
    git -C "$HISTORY_ROOT" config user.name 'Rafex ThinkPad'
    git -C "$HISTORY_ROOT" config user.email 'rafex-thinkpad@localhost'
  fi
  if [[ ! -e "$HISTORY_ROOT/.gitignore" ]]; then
    printf '%s\n' '*.tmp' '*.bak' '*.swp' '.history.lock' > "$HISTORY_ROOT/.gitignore"
    chmod 600 -- "$HISTORY_ROOT/.gitignore"
  elif ! grep -Fqx '.history.lock' "$HISTORY_ROOT/.gitignore"; then
    printf '%s\n' '.history.lock' >> "$HISTORY_ROOT/.gitignore"
    chmod 600 -- "$HISTORY_ROOT/.gitignore"
    gitignore_changed=1
  fi
  if (( gitignore_changed )) && git -C "$HISTORY_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$HISTORY_ROOT" add -- .gitignore
    git -C "$HISTORY_ROOT" commit -q -m 'chore: ignore history lock'
  fi
  if ! git -C "$HISTORY_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$HISTORY_ROOT" add -- .gitignore
    git -C "$HISTORY_ROOT" commit -q -m 'init: ThinkPad installed history'
  fi
}

sync_checkout() {
  [[ -d "$REPO_ROOT/.git" ]] || die 'no existe el checkout ejecutor del repositorio'
  git -C "$REPO_ROOT" diff --quiet || die 'el checkout ejecutor tiene cambios sin commit'
  git -C "$REPO_ROOT" diff --cached --quiet || die 'el checkout ejecutor tiene cambios staged'
  history_init
  validate_repo
  ok "fuente ejecutora validada: $REPO_ROOT"
  ok "historial local listo: $HISTORY_ROOT"
}

create_backup_root() {
  BACKUP_ROOT="$PUBLISH_STATE_DIR/backups/$STAMP"
  mkdir -p -- "$BACKUP_ROOT"
  chmod 700 -- "$PUBLISH_STATE_DIR" "$PUBLISH_STATE_DIR/backups" "$BACKUP_ROOT"
  printf '%s\n' "$BACKUP_ROOT" > "$PUBLISH_STATE_DIR/last-backup"
  chmod 600 -- "$PUBLISH_STATE_DIR/last-backup"
}

source_path() { printf '%s/%s\n' "$(repo_root)" "$1"; }
installed_path() { printf '%s/home/%s\n' "$INSTALLED_ROOT" "$1"; }

stage_installed_artifact() {
  local source="$1" target_relative="$2" mode="$3" allowed_root="$4" destination temporary
  destination="$(installed_path "$target_relative")"
  rafex_publish_assert_inside "$source" "$allowed_root"
  mkdir -p -- "$(dirname -- "$destination")"
  if [[ -f "$destination" ]] && cmp -s -- "$source" "$destination"; then
    chmod "$mode" -- "$destination"
    printf '%s\n' "$destination"
    return 0
  fi
  temporary="$(mktemp "$(dirname -- "$destination")/.rafex-installed.XXXXXX")"
  cp -p -- "$source" "$temporary"
  chmod "$mode" -- "$temporary"
  mv -f -- "$temporary" "$destination"
  printf '%s\n' "$destination"
}

history_commit() {
  local revision
  revision="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf unknown)"
  printf '%s\n' "$revision" > "$HISTORY_ROOT/source-revision"
  chmod 600 -- "$HISTORY_ROOT/source-revision"
  git -C "$HISTORY_ROOT" add -- .gitignore installed source-revision
  if ! git -C "$HISTORY_ROOT" diff --cached --quiet; then
    git -C "$HISTORY_ROOT" commit -q -m "deploy: source $revision"
  fi
}
target_path() {
  case "$1" in
    .config/*) printf '%s/%s\n' "$CONFIG_HOME" "${1#.config/}" ;;
    .local/bin/*) printf '%s/%s\n' "$HOME/.local/bin" "${1#.local/bin/}" ;;
    *) die "destino no permitido en manifiesto: $1" ;;
  esac
}

validate_manifest() {
  local kind resource source target mode source_file target_file
  awk -F'|' '
    /^#/ || NF == 0 {next}
    {resources[$2]++; targets[$4]++}
    END {
      for (key in resources) if (resources[key] > 1) {print "recurso duplicado: " key; bad=1}
      for (key in targets) if (targets[key] > 1) {print "destino duplicado: " key; bad=1}
      exit bad
    }
  ' "$(source_path "$MANIFEST_REL")" || die 'manifiesto con propietarios o destinos duplicados'
  while IFS='|' read -r kind resource source target mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    [[ "$kind" == static || "$kind" == generated ]] || die "estrategia inválida en manifiesto: $kind"
    [[ "$resource" =~ ^[a-z0-9._-]+$ ]] || die "recurso inválido en manifiesto: $resource"
    [[ "$source" != /* && "$source" != *..* ]] || die "fuente insegura en manifiesto: $source"
    [[ "$target" != /* && "$target" != *..* ]] || die "destino inseguro en manifiesto: $target"
    [[ "$mode" =~ ^0[0-7]{3}$ ]] || die "modo inválido en manifiesto: $mode"
    source_file="$(source_path "$source")"
    target_file="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      [[ -f "$source_file" ]] || die "fuente del manifiesto ausente: $source_file"
    else
      [[ "$source" == @generated/* ]] || die "los generados deben usar @generated/: $source"
    fi
    printf '%s|%s|%s|%s|%s\n' "$kind" "$resource" "$source_file" "$target_file" "$mode"
  done < "$(source_path "$MANIFEST_REL")"
}

generate_i3_tree() {
  local root="$1" i3_source i3_dir fragment_dir staging temporary
  i3_source="$root/$PROFILE/config/i3/config"
  if (( ALLOW_ADOPT )) && [[ -f "$TARGET_I3" ]] && ! rafex_i3_fragment_is_active "$TARGET_I3"; then
    i3_source="$TARGET_I3"
  fi
  i3_dir="$GENERATED_ROOT/i3"
  fragment_dir="$i3_dir/fragments"
  mkdir -p -- "$i3_dir" "$fragment_dir"
  chmod 700 -- "$i3_dir" "$fragment_dir"
  staging="$(mktemp -d "$GENERATED_ROOT/.i3-staging.XXXXXX")"
  # La biblioteca común conoce las variantes históricas de los marcadores
  # (por ejemplo, controles y panel). Así `--adopt` no pierde integraciones
  # existentes al convertir i3 en una composición por fragmentos.
  rafex_i3_fragment_seed "$i3_source"
  temporary="$(mktemp "$staging/config.XXXXXX")"
  {
    printf '%s\n' "$RAFEX_I3_FRAGMENT_COMPOSED_MARKER"
    printf '%s\n' '# Generated by rafex_config_linux.sh; edit the repository, not this file.'
    printf '%s\n' 'include ~/.local/state/rafex/config-generated/thinkpad/i3/base.conf'
    for name in controls gaps launcher theme conky eww wallpaper lock clipboard screenshots ratmenu control-panel autorotate xrandr-brightness udiskie picom; do
      if [[ -s "$fragment_dir/$name.conf" ]]; then
        printf 'include ~/.local/state/rafex/config-generated/thinkpad/i3/fragments/%s.conf\n' "$name"
      fi
    done
    printf '%s\n' 'include ~/.config/i3/rafex-bar-active.conf'
  } > "$temporary"
  mv -f -- "$temporary" "$i3_dir/config"
  rmdir -- "$staging"
  chmod 600 -- "$i3_dir/config" "$fragment_dir"/*.conf 2>/dev/null || true
}

generate_dynamic_files() {
  local root="$1" theme='nord' theme_file bar_source
  mkdir -p -- "$GENERATED_ROOT"
  if [[ -f "$CONFIG_HOME/rafex/theme" ]]; then theme="$(head -n 1 "$CONFIG_HOME/rafex/theme")"; fi
  [[ "$theme" =~ ^(paper|nord|everforest|dracula)$ ]] || theme=nord
  local temporary
  temporary="$(mktemp "$GENERATED_ROOT/.eww.scss.XXXXXX")"
  if (( ALLOW_ADOPT )) && [[ -f "$CONFIG_HOME/eww/eww.scss" && ! -L "$CONFIG_HOME/eww/eww.scss" ]]; then
    install -m 0600 -- "$CONFIG_HOME/eww/eww.scss" "$temporary"
  else
    theme_file="$root/$PROFILE/config/rafex/themes/$theme/eww.scss"
    [[ -f "$theme_file" ]] || theme_file="$root/$PROFILE/config/rafex/themes/nord/eww.scss"
    install -m 0600 -- "$theme_file" "$temporary"
  fi
  mv -f -- "$temporary" "$GENERATED_ROOT/eww.scss"
  bar_source='polybar'
  if [[ -f "$CONFIG_HOME/rafex/i3-bar-profile" ]]; then bar_source="$(head -n 1 "$CONFIG_HOME/rafex/i3-bar-profile")"; fi
  [[ "$bar_source" =~ ^(i3bar|tint2|polybar)$ ]] || bar_source=polybar
  temporary="$(mktemp "$GENERATED_ROOT/.i3-bar-profile.XXXXXX")"
  printf '%s\n' "$bar_source" > "$temporary"
  mv -f -- "$temporary" "$GENERATED_ROOT/i3-bar-profile"
  chmod 600 -- "$GENERATED_ROOT/i3-bar-profile"
  generate_i3_tree "$root"
}

show_status() {
  local root kind resource source target target_relative mode
  root="$(repo_root)"
  printf 'source=%s\n' "$REPO_ROOT"
  printf 'history=%s\n' "$HISTORY_ROOT"
  printf 'installed=%s\n' "$INSTALLED_ROOT"
  printf 'generated=%s\n' "$GENERATED_ROOT"
  if [[ -d "$HISTORY_ROOT/.git" ]]; then
    if history_clean; then printf 'history-clean=yes\n'; else printf 'history-clean=no\n'; fi
    printf 'history-revision=%s\n' "$(git -C "$HISTORY_ROOT" rev-parse --short HEAD 2>/dev/null || printf none)"
  else
    printf 'history=not-initialized\n'
  fi
  while IFS='|' read -r kind resource source target mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    target_relative="$target"
    target="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      if rafex_publish_is_exact_symlink "$target" "$(installed_path "$target_relative")"; then printf '%s=managed-symlink\n' "$resource"; else printf '%s=unmanaged-or-missing\n' "$resource"; fi
    else
      if [[ -L "$target" || -f "$target" ]]; then printf '%s=present\n' "$resource"; else printf '%s=missing\n' "$resource"; fi
    fi
  done < "$(source_path "$MANIFEST_REL")"
  [[ -f "$PUBLISH_STATE_DIR/last-backup" ]] && printf 'last-backup=%s\n' "$(<"$PUBLISH_STATE_DIR/last-backup")" || printf 'last-backup=none\n'
}

show_plan() {
  local root
  root="$(repo_root)"
  printf '═══ Plan de publicación Rafex ThinkPad ═══\n'
  printf 'fuente ejecutora: %s\n' "$root"
  printf 'historial local: %s\n' "$HISTORY_ROOT"
  printf 'artefactos instalados: %s\n' "$INSTALLED_ROOT"
  printf 'generados: %s\n' "$GENERATED_ROOT"
  printf '%s\n' '1. validar manifiesto y propietario único'
  printf '%s\n' '2. generar i3 por fragmentos y EWW/bar dinámicos en estado Rafex'
  printf '%s\n' '3. publicar archivos estáticos como symlinks administrados'
  printf '%s\n' '4. publicar destinos dinámicos atómicamente'
  printf '%s\n' '5. rechazar destinos manuales salvo --adopt explícito'
  printf '%s\n' 'No se ejecutan sudo, git commit, git push, reinicios ni cambios de hardware.'
}

publish_all() {
  local root kind resource source target target_relative mode installed_source
  root="$(repo_root)"
  validate_manifest >/dev/null
  history_init
  history_clean || die 'el historial local está modificado fuera del publicador'
  create_backup_root
  if [[ -d "$GENERATED_ROOT" ]]; then
    while IFS= read -r -d '' source; do
      rafex_publish_backup "$source" "${source#"$HOME/"}" "$BACKUP_ROOT" >/dev/null || true
    done < <(find "$GENERATED_ROOT" \( -type f -o -type l \) -print0)
  fi
  generate_dynamic_files "$root"
  while IFS='|' read -r kind resource source target mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    target_relative="$target"
    source="$(source_path "$source")"
    target="$(target_path "$target_relative")"
    if [[ "$kind" == static ]]; then
      installed_source="$(installed_path "$target_relative")"
      rafex_publish_refuse_unmanaged "$target" "$installed_source" "$ALLOW_ADOPT"
      rafex_publish_backup "$installed_source" ".installed/$target_relative" "$BACKUP_ROOT" >/dev/null || true
      stage_installed_artifact "$source" "$target_relative" "$mode" "$REPO_ROOT" >/dev/null
      rafex_publish_install_symlink "$installed_source" "$target" "$mode" "$ALLOW_ADOPT" "${target#"$HOME/"}" "$BACKUP_ROOT"
    else
      local generated
      generated="$GENERATED_ROOT/$resource.generated"
      case "$resource" in
        i3-config) generated="$GENERATED_ROOT/i3/config" ;;
        eww-style) generated="$GENERATED_ROOT/eww.scss" ;;
        bar-state) generated="$GENERATED_ROOT/i3-bar-profile" ;;
      esac
      # Los dinámicos deben enlazar al árbol generado: los instaladores de
      # fragmentos actualizan ese árbol después del despliegue. Copiarlos a
      # installed/ dejaría el enlace apuntando a una versión obsoleta.
      rafex_publish_refuse_unmanaged "$target" "$generated" "$ALLOW_ADOPT"
      rafex_publish_backup "$target" "generated/$target_relative" "$BACKUP_ROOT" >/dev/null || true
      rafex_publish_install_generated "$generated" "$target" "$mode" "$ALLOW_ADOPT" "${target#"$HOME/"}" "$BACKUP_ROOT"
    fi
  done < "$(source_path "$MANIFEST_REL")"
  history_commit
  ok 'publicación completada'
}

doctor() {
  local failures=0 target source resource kind target_relative
  validate_manifest >/dev/null || failures=$((failures + 1))
  history_clean || failures=$((failures + 1))
  while IFS='|' read -r kind resource source target _mode; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    target_relative="$target"
    target="$(target_path "$target")"
    if [[ "$kind" == static ]]; then
      source="$(installed_path "$target_relative")"
      if [[ -L "$target" ]]; then
        if [[ ! -e "$target" ]]; then
          warn "$resource: enlace roto"
          failures=$((failures + 1))
          continue
        fi
        rafex_publish_assert_inside "$(readlink -f -- "$target")" "$INSTALLED_ROOT" || failures=$((failures + 1))
        rafex_publish_is_exact_symlink "$target" "$source" || { warn "$resource: enlace apunta a otra fuente"; failures=$((failures + 1)); }
      elif [[ -e "$target" ]]; then
        warn "$resource: archivo manual en lugar de symlink"
        failures=$((failures + 1))
      fi
    else
      local generated
      case "$resource" in
        i3-config) generated="$GENERATED_ROOT/i3/config" ;;
        eww-style) generated="$GENERATED_ROOT/eww.scss" ;;
        bar-state) generated="$GENERATED_ROOT/i3-bar-profile" ;;
        *) generated='' ;;
      esac
      if [[ -n "$generated" && -L "$target" ]]; then
        if [[ ! -e "$target" ]]; then
          warn "$resource: enlace generado roto"
          failures=$((failures + 1))
          continue
        fi
        rafex_publish_assert_inside "$(readlink -f -- "$target")" "$GENERATED_ROOT" || failures=$((failures + 1))
        [[ "$(readlink -f -- "$target")" == "$(realpath -m -- "$generated")" ]] || { warn "$resource: enlace generado incorrecto"; failures=$((failures + 1)); }
      elif [[ -n "$generated" && -e "$target" ]]; then
        warn "$resource: archivo manual en lugar de symlink generado"
        failures=$((failures + 1))
      fi
    fi
  done < "$(source_path "$MANIFEST_REL")"
  if [[ -f "$TARGET_I3" ]] && [[ -L "$TARGET_I3" ]] && ! grep -Fq 'Generated by rafex_config_linux.sh' "$TARGET_I3"; then
    warn 'i3 config: el enlace no apunta al árbol generado Rafex'
    failures=$((failures + 1))
  fi
  if (( failures == 0 )); then ok 'doctor: sin conflictos detectados'; else return 1; fi
}

rollback() {
  local root relative backup target
  [[ -f "$PUBLISH_STATE_DIR/last-backup" ]] || die 'no existe un respaldo del publicador'
  root="$(<"$PUBLISH_STATE_DIR/last-backup")"
  [[ -d "$root" ]] || die "respaldo ausente: $root"
  while IFS= read -r -d '' backup; do
    relative="${backup#"$root/"}"
    case "$relative" in
      .installed/*) target="$INSTALLED_ROOT/home/${relative#.installed/}" ;;
      *) target="$HOME/$relative" ;;
    esac
    mkdir -p -- "$(dirname -- "$target")"
    rm -f -- "$target"
    cp -a -- "$backup" "$target"
    rafex_publish_log rollback "$relative" "$target" absent "$(rafex_publish_sha256 "$target")" "backup=$backup"
  done < <(find "$root" \( -type f -o -type l \) -print0)
  ok "rollback restaurado: $root"
}

main() {
  parse_args "$@"
  require_linux
  [[ -f "$REPO_ROOT/$PROFILE/rafex-config-manifest.tsv" ]] || die 'manifiesto ThinkPad ausente'
  case "$ACTION" in
    check)
      validate_repo
      validate_manifest >/dev/null
      if [[ -d "$HISTORY_ROOT/.git" ]]; then history_clean || exit 1; fi
      ok 'manifiesto, fuentes, rutas y checkout válidos'
      ;;
    status) validate_repo; show_status ;;
    plan) validate_repo; show_plan ;;
    sync) require_lock_tool; rafex_publish_lock; sync_checkout ;;
    adopt) require_lock_tool; rafex_publish_lock; sync_checkout; validate_repo; ALLOW_ADOPT=1; publish_all ;;
    deploy)
      require_lock_tool
      rafex_publish_lock
      sync_checkout
      validate_repo
      publish_all
      ;;
    rollback) require_lock_tool; rafex_publish_lock; rollback ;;
    doctor) validate_repo; doctor ;;
  esac
}

main "$@"
