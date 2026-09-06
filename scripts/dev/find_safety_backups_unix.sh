#!/usr/bin/env bash
# shellcheck shell=bash
# Encuentra y borra (en bloque o uno por uno) los respaldos .bak.<fecha> que
# otros scripts de este repo dejan junto al archivo que van a sobrescribir.
set -Eeuo pipefail
umask 077

ACTION="check"
ALL=0
INCLUDE_SYSTEM=0
ROOTS_OVERRIDE=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso:
  find_safety_backups_unix.sh --check
  find_safety_backups_unix.sh --plan [--include-system]
  find_safety_backups_unix.sh --apply --all
  find_safety_backups_unix.sh --apply

Encuentra respaldos "<archivo>.bak.<fecha>" colocados junto al archivo que
otros scripts de este repo modifican antes de sobrescribirlo, y permite
borrarlos todos de una vez (--apply --all) o uno por uno con un selector
interactivo (--apply, sin --all).

Opciones:
  --check              Audita sin modificar (default).
  --plan | --dry-run   Igual que --check, mostrando qué se borraría.
  --apply              Habilita el borrado. Sin --all, entra al selector
                        interactivo.
  --all                Junto con --apply, borra todo lo encontrado.
  --include-system     Agrega /etc a las raíces de búsqueda (root-owned).
  --roots DIR[,DIR...] Reemplaza la lista de raíces de búsqueda.
  --help, -h           Muestra esta ayuda.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check) ACTION="check" ;;
      --plan|--dry-run) ACTION="plan" ;;
      --apply) ACTION="apply" ;;
      --all) ALL=1 ;;
      --include-system) INCLUDE_SYSTEM=1 ;;
      --roots)
        [[ $# -ge 2 ]] || die "--roots requiere un valor"
        ROOTS_OVERRIDE="$2"
        shift
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
    shift
  done
  [[ "$ALL" -eq 0 || "$ACTION" == apply ]] || die '--all requiere --apply'
}

# ─────────────────────────────────────────────────────────────────────────
# Rutas excluidas siempre (aunque se pase --roots): son raíces dedicadas de
# otros mecanismos de respaldo, fuera de alcance de este script.
# ─────────────────────────────────────────────────────────────────────────
is_excluded_path() {
  local path="$1"
  case "$path" in
    "$HOME"/.cache|"$HOME"/.cache/*) return 0 ;;
    "$HOME"/.git|"$HOME"/.git/*) return 0 ;;
    "$HOME"/.cargo|"$HOME"/.cargo/*) return 0 ;;
    "$HOME"/.rustup|"$HOME"/.rustup/*) return 0 ;;
    "$HOME"/.npm|"$HOME"/.npm/*) return 0 ;;
    "$HOME"/.local/share/mise|"$HOME"/.local/share/mise/*) return 0 ;;
    "$HOME"/.local/share/java-runtimes|"$HOME"/.local/share/java-runtimes/*) return 0 ;;
    "$HOME"/.local/share/node-runtimes|"$HOME"/.local/share/node-runtimes/*) return 0 ;;
    "$HOME"/.local/share/build-runtimes|"$HOME"/.local/share/build-runtimes/*) return 0 ;;
    "$HOME"/.local/share/containers|"$HOME"/.local/share/containers/*) return 0 ;;
    "$HOME"/.local/share/npm-global|"$HOME"/.local/share/npm-global/*) return 0 ;;
    "$HOME"/.local/share/rafex/eww|"$HOME"/.local/share/rafex/eww/*) return 0 ;;
    "$HOME"/.local/state/rafex/backups|"$HOME"/.local/state/rafex/backups/*) return 0 ;;
    "$HOME"/.opencode/rafex-update-*) return 0 ;;
    /var/backups|/var/backups/*) return 0 ;;
    */node_modules|*/node_modules/*) return 0 ;;
  esac
  return 1
}

# Mismos directorios que is_excluded_path(), en forma de predicado -path
# para que find() no los recorra (rendimiento + no tropezar con permisos
# de otras herramientas dentro de esas raíces).
find_prune_predicate() {
  cat <<EOF
$HOME/.cache
$HOME/.cache/*
$HOME/.git
$HOME/.git/*
$HOME/.cargo
$HOME/.cargo/*
$HOME/.rustup
$HOME/.rustup/*
$HOME/.npm
$HOME/.npm/*
$HOME/.local/share/mise
$HOME/.local/share/mise/*
$HOME/.local/share/java-runtimes
$HOME/.local/share/java-runtimes/*
$HOME/.local/share/node-runtimes
$HOME/.local/share/node-runtimes/*
$HOME/.local/share/build-runtimes
$HOME/.local/share/build-runtimes/*
$HOME/.local/share/containers
$HOME/.local/share/containers/*
$HOME/.local/share/npm-global
$HOME/.local/share/npm-global/*
$HOME/.local/share/rafex/eww
$HOME/.local/share/rafex/eww/*
$HOME/.local/state/rafex/backups
$HOME/.local/state/rafex/backups/*
$HOME/.opencode/rafex-update-*
/var/backups
/var/backups/*
*/node_modules
*/node_modules/*
EOF
}

# Raíces de búsqueda por defecto: los respaldos colocados siempre viven
# junto a un archivo de configuración, y por catálogo eso significa
# ~/.config, ~/.local/share, o un dotfile directo en $HOME (p. ej.
# .bashrc.bak.<fecha>) — nunca dentro de árboles de proyecto/build
# arbitrarios que el usuario tenga en su home. Por eso $HOME propio se
# escanea solo a profundidad 1 (sin bajar a proyectos), mientras que
# .config y .local/share sí se recorren completos (con las exclusiones de
# arriba). Cada entrada es "ruta|profundidad" (profundidad vacía = sin límite).
build_search_roots() {
  SEARCH_ROOTS=()
  if [[ -n "$ROOTS_OVERRIDE" ]]; then
    local -a overrides=()
    IFS=',' read -ra overrides <<<"$ROOTS_OVERRIDE"
    local r
    for r in "${overrides[@]}"; do
      SEARCH_ROOTS+=("${r}|")
    done
  else
    SEARCH_ROOTS=("$HOME/.config|" "$HOME/.local/share|" "$HOME|1")
    [[ "$INCLUDE_SYSTEM" -eq 1 ]] && SEARCH_ROOTS+=("/etc|")
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────
# Detección exacta de los dos formatos conocidos de respaldo:
#   <archivo>.bak.YYYYMMDD_HHMMSS[.N]
#   <archivo>.bak-YYYYMMDD-HHMMSS.XXXXXX   (variante mktemp)
# ─────────────────────────────────────────────────────────────────────────
is_backup_name() {
  local name="$1"
  [[ "$name" =~ \.bak\.[0-9]{8}_[0-9]{6}(\.[0-9]+)?$ ]] && return 0
  [[ "$name" =~ \.bak-[0-9]{8}-[0-9]{6}\.[A-Za-z0-9]{6}$ ]] && return 0
  return 1
}

strip_backup_suffix() {
  printf '%s\n' "$1" | sed -E \
    -e 's/\.bak\.[0-9]{8}_[0-9]{6}(\.[0-9]+)?$//' \
    -e 's/\.bak-[0-9]{8}-[0-9]{6}\.[A-Za-z0-9]{6}$//'
}

os_stat_size_mtime() {
  local path="$1"
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%z %m' -- "$path"
  else
    stat -c '%s %Y' -- "$path"
  fi
}

human_size() {
  awk -v b="$1" 'BEGIN{
    split("B K M G T", u, " ");
    v = b; i = 1
    while (v >= 1024 && i < 5) { v /= 1024; i++ }
    if (i == 1) printf "%d%s", v, u[i]; else printf "%.1f%s", v, u[i]
  }'
}

human_age() {
  local mtime="$1" now diff
  now="$(date +%s)"
  diff=$(( now - mtime ))
  (( diff >= 0 )) || diff=0
  if (( diff < 60 )); then printf '%ds' "$diff"
  elif (( diff < 3600 )); then printf '%dm' $(( diff / 60 ))
  elif (( diff < 86400 )); then printf '%dh' $(( diff / 3600 ))
  else printf '%dd' $(( diff / 86400 ))
  fi
}

FINDINGS=()

emit_finding() {
  local path="$1" size mtime original original_exists scope
  read -r size mtime < <(os_stat_size_mtime "$path")
  original="$(strip_backup_suffix "$path")"
  if [[ -e "$original" ]]; then original_exists=si; else original_exists=no; fi
  case "$path" in
    "$HOME"/*) scope=user ;;
    *) scope=system ;;
  esac
  FINDINGS+=("$path"$'\t'"$size"$'\t'"$mtime"$'\t'"$original"$'\t'"$original_exists"$'\t'"$scope")
}

find_backups_in_root() {
  local root="$1" maxdepth="$2"
  [[ -e "$root" ]] || { warn "raíz no existe: $root"; return 0; }
  local -a prune_args=() known_backup_dirs=() find_opts=()
  local p first=1
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ "$first" -eq 1 ]] || prune_args+=(-o)
    prune_args+=(-path "$p")
    first=0
  done < <(find_prune_predicate)

  find_opts=(-mindepth 1)
  [[ -n "$maxdepth" ]] && find_opts+=(-maxdepth "$maxdepth")

  local path name skip kd
  while IFS= read -r -d '' path; do
    is_excluded_path "$path" && continue
    skip=0
    if (( ${#known_backup_dirs[@]} > 0 )); then
      for kd in "${known_backup_dirs[@]}"; do
        case "$path" in "$kd"/*) skip=1; break ;; esac
      done
    fi
    [[ "$skip" -eq 1 ]] && continue
    name="$(basename -- "$path")"
    if is_backup_name "$name"; then
      emit_finding "$path"
      if [[ -d "$path" ]]; then
        known_backup_dirs+=("$path")
      fi
    fi
  done < <(find "$root" "${find_opts[@]}" \( "${prune_args[@]}" \) -prune -o -print0)
  return 0
}

find_backups() {
  local entry root maxdepth
  for entry in "${SEARCH_ROOTS[@]}"; do
    root="${entry%|*}"
    maxdepth="${entry##*|}"
    find_backups_in_root "$root" "$maxdepth"
  done
  return 0
}

show_findings() {
  local mode="$1" i=0 total_bytes=0 entry path size mtime original original_exists scope
  if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    info 'no se encontraron respaldos .bak.<fecha>'
    return 0
  fi
  for entry in "${FINDINGS[@]}"; do
    i=$((i + 1))
    IFS=$'\t' read -r path size mtime original original_exists scope <<<"$entry"
    total_bytes=$((total_bytes + size))
    if [[ "$mode" == pick ]]; then
      printf '[%d] %s\n' "$i" "$path"
    else
      printf '%s\n' "$path"
    fi
    printf '    tamaño=%s edad=%s original=%s (%s) scope=%s\n' \
      "$(human_size "$size")" "$(human_age "$mtime")" "$original" \
      "$([[ "$original_exists" == si ]] && printf presente || printf ausente)" "$scope"
    [[ "$mode" == plan ]] && info "[plan] eliminar $path"
  done
  printf '\nTotal: %d hallazgo(s), %s\n' "${#FINDINGS[@]}" "$(human_size "$total_bytes")"
}

confirm() {
  local msg="$1" answer
  printf '%s [y/N]: ' "$msg"
  read -r answer || answer=n
  [[ "$answer" =~ ^[Yy]$ ]]
}

delete_path() {
  local path="$1" scope="$2" name
  name="$(basename -- "$path")"
  is_backup_name "$name" || die "no se elimina $path: el nombre ya no coincide con el patrón esperado"
  is_excluded_path "$path" && die "no se elimina $path: ruta excluida"
  if [[ "$scope" == system ]]; then
    sudo rm -rf -- "$path"
  else
    rm -rf -- "$path"
  fi
  ok "eliminado: $path"
}

any_system_scope() {
  local entry scope
  if (( ${#FINDINGS[@]} > 0 )); then
    for entry in "${FINDINGS[@]}"; do
      IFS=$'\t' read -r _ _ _ _ _ scope <<<"$entry"
      [[ "$scope" == system ]] && return 0
    done
  fi
  return 1
}

delete_all() {
  any_system_scope && sudo -v
  local entry path scope
  if (( ${#FINDINGS[@]} > 0 )); then
    for entry in "${FINDINGS[@]}"; do
      IFS=$'\t' read -r path _ _ _ _ scope <<<"$entry"
      delete_path "$path" "$scope"
    done
  fi
  return 0
}

# Interpreta la selección del usuario: índices sueltos, rangos/listas
# ("1", "1,3", "1-3"), "todo"/"a" (todos), o "q"/"salir" (salir).
# Emite los índices válidos (1-based) en stdout, uno por línea.
# Códigos de salida: 0 = ok, 1 = selección inválida, 2 = salir.
parse_selection() {
  local input="$1" max_n="$2"
  case "$input" in
    q|Q|quit|salir) return 2 ;;
    a|A|todo|all)
      seq 1 "$max_n"
      return 0
      ;;
  esac
  local -a parts=() out=()
  IFS=',' read -ra parts <<<"$input"
  local part start end idx
  if (( ${#parts[@]} > 0 )); then
    for part in "${parts[@]}"; do
      part="$(printf '%s' "$part" | tr -d '[:space:]')"
      [[ -n "$part" ]] || continue
      if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
        (( start >= 1 && end <= max_n && start <= end )) || return 1
        for (( idx = start; idx <= end; idx++ )); do out+=("$idx"); done
      elif [[ "$part" =~ ^[0-9]+$ ]]; then
        (( part >= 1 && part <= max_n )) || return 1
        out+=("$part")
      else
        return 1
      fi
    done
  fi
  (( ${#out[@]} > 0 )) || return 1
  printf '%s\n' "${out[@]}"
  return 0
}

interactive_picker() {
  while (( ${#FINDINGS[@]} > 0 )); do
    show_findings pick
    printf '\nSelecciona índice(s) (ej. 1 / 1,3 / 1-3), "todo", o "q" para salir: '
    local input
    if ! read -r input; then break; fi
    local selection rc=0
    selection="$(parse_selection "$input" "${#FINDINGS[@]}")" || rc=$?
    if [[ "$rc" -eq 2 ]]; then
      info 'saliendo sin más cambios'
      break
    elif [[ "$rc" -ne 0 ]]; then
      warn 'selección inválida, intenta de nuevo'
      continue
    fi
    local count
    count="$(printf '%s\n' "$selection" | grep -c .)"
    confirm "¿Eliminar $count respaldo(s) seleccionados?" || { info 'cancelado'; continue; }

    local -a idx_desc=()
    local idx_line
    while IFS= read -r idx_line; do
      [[ -n "$idx_line" ]] && idx_desc+=("$idx_line")
    done < <(printf '%s\n' "$selection" | sort -rn)
    local idx entry path scope has_system=0
    if (( ${#idx_desc[@]} > 0 )); then
      for idx in "${idx_desc[@]}"; do
        entry="${FINDINGS[$((idx - 1))]}"
        IFS=$'\t' read -r _ _ _ _ _ scope <<<"$entry"
        [[ "$scope" == system ]] && has_system=1
      done
    fi
    [[ "$has_system" -eq 0 ]] || sudo -v
    if (( ${#idx_desc[@]} > 0 )); then
      for idx in "${idx_desc[@]}"; do
        entry="${FINDINGS[$((idx - 1))]}"
        IFS=$'\t' read -r path _ _ _ _ scope <<<"$entry"
        delete_path "$path" "$scope"
        unset 'FINDINGS[idx-1]'
      done
    fi
    if (( ${#FINDINGS[@]} > 0 )); then
      FINDINGS=("${FINDINGS[@]}")
    fi
  done
  return 0
}

main() {
  parse_args "$@"
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die 'ejecuta el script como usuario normal; sudo se usa internamente'
  build_search_roots
  find_backups
  case "$ACTION" in
    check) show_findings check ;;
    plan) show_findings plan ;;
    apply)
      show_findings check
      if [[ ${#FINDINGS[@]} -eq 0 ]]; then
        info 'nada que borrar'
      elif [[ "$ALL" -eq 1 ]]; then
        delete_all
        ok 'limpieza completada'
      else
        interactive_picker
        ok 'limpieza completada'
      fi
      ;;
  esac
}

main "$@"
