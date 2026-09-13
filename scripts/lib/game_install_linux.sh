#!/usr/bin/env bash
# shellcheck shell=bash
# Biblioteca interna para instaladores de juegos rootless de Rafex.
set -Eeuo pipefail
umask 077

: "${GI_GAME_NAME:?GI_GAME_NAME no está definido}"
: "${GI_SLUG:?GI_SLUG no está definido}"
: "${GI_VERSION:?GI_VERSION no está definido}"
: "${GI_ARCHIVE_NAME:?GI_ARCHIVE_NAME no está definido}"
: "${GI_DOWNLOAD_URL:?GI_DOWNLOAD_URL no está definido}"
: "${GI_INSTALL_DIR:?GI_INSTALL_DIR no está definido}"
: "${GI_REQUIRED_ROOT:?GI_REQUIRED_ROOT no está definido}"
: "${GI_RUN_RELATIVE:?GI_RUN_RELATIVE no está definido}"
: "${GI_DESKTOP_NAME:?GI_DESKTOP_NAME no está definido}"
: "${GI_LAUNCHER_NAME:?GI_LAUNCHER_NAME no está definido}"
: "${GI_CHECKSUM_ALGO:?GI_CHECKSUM_ALGO no está definido}"
: "${GI_EXPECTED_CHECKSUM:?GI_EXPECTED_CHECKSUM no está definido}"

GI_ACTION='check'
GI_UPGRADE='no'
GI_ARCHIVE_OVERRIDE=''
GI_STAGE_DIR=''
GI_ARCHIVE=''
GI_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rafex/games/${GI_SLUG}"
GI_GAMES_DIR="$(dirname -- "$GI_INSTALL_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
gi_info() { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
gi_ok() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
gi_warn() { echo -e "${YELLOW}${BOLD}⚠${RESET} $*" >&2; }
gi_die() { echo -e "${RED}${BOLD}✗ ERROR:${RESET} $*" >&2; exit 1; }

gi_usage() {
  cat <<EOF
Uso:
  ${GI_SLUG}_linux.sh --check|--plan|--status|--rollback
  ${GI_SLUG}_linux.sh --apply [--upgrade] [--archive <archivo>]

Opciones:
  --check                  Diagnóstico y verificación sin escribir (default)
  --plan                   Mostrar operaciones sin descargar ni instalar
  --apply                  Instalar dependencias y el juego como usuario normal
  --upgrade                Permitir reemplazar una instalación administrada
  --archive <archivo>      Usar explícitamente un ZIP local
  --status                 Mostrar instalación, checksum y dependencias
  --rollback               Restaurar el último respaldo administrado
  -h|--help                Mostrar esta ayuda
EOF
}

gi_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) GI_ACTION='check'; shift;;
      --plan|--dry-run) GI_ACTION='plan'; shift;;
      --apply) GI_ACTION='apply'; shift;;
      --status) GI_ACTION='status'; shift;;
      --rollback) GI_ACTION='rollback'; shift;;
      --upgrade) GI_UPGRADE='yes'; shift;;
      --archive) [[ $# -ge 2 ]] || gi_die 'falta el valor de --archive'; GI_ARCHIVE_OVERRIDE="$2"; shift 2;;
      -h|--help) gi_usage; exit 0;;
      *) gi_die "argumento desconocido: $1";;
    esac
  done
}

gi_require_base() {
  [[ "$(uname -s)" == 'Linux' ]] || gi_die 'este instalador solo funciona en Debian Linux'
  [[ -r /etc/os-release ]] || gi_die 'no se puede leer /etc/os-release'
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == 'debian' ]] || gi_die "distribución no soportada: ${ID:-desconocida}"
  [[ "$(dpkg --print-architecture 2>/dev/null)" == 'amd64' ]] || gi_die 'se requiere arquitectura Debian amd64'
  local command_name
  for command_name in awk date dirname file find install ldd mktemp mv realpath sha256sum unzip zipinfo; do
    command -v "$command_name" >/dev/null 2>&1 || gi_die "falta la herramienta: $command_name"
  done
  if [[ "$GI_CHECKSUM_ALGO" == 'sha512' ]]; then command -v sha512sum >/dev/null 2>&1 || gi_die 'falta sha512sum'; else command -v md5sum >/dev/null 2>&1 || gi_die 'falta md5sum'; fi
  if [[ "$GI_ACTION" == 'apply' ]]; then
    command -v sudo >/dev/null 2>&1 || gi_die 'sudo no está instalado'
    command -v apt-get >/dev/null 2>&1 || gi_die 'apt-get no está disponible'
    command -v apt-cache >/dev/null 2>&1 || gi_die 'apt-cache no está disponible'
    command -v dpkg-query >/dev/null 2>&1 || gi_die 'dpkg-query no está disponible'
  fi
}

gi_download_tool() { if command -v curl >/dev/null 2>&1; then printf '%s\n' curl; elif command -v wget >/dev/null 2>&1; then printf '%s\n' wget; else return 1; fi; }
gi_download_dirs() {
  local xdg_download=''
  if command -v xdg-user-dir >/dev/null 2>&1; then xdg_download="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"; fi
  [[ -n "$xdg_download" ]] && printf '%s\n' "$xdg_download"
  printf '%s\n' "$HOME/Descargas" "$HOME/Downloads"
}

gi_find_archive() {
  local candidate directory
  if [[ -n "$GI_ARCHIVE_OVERRIDE" ]]; then
    [[ -f "$GI_ARCHIVE_OVERRIDE" ]] || gi_die "archivo no encontrado: $GI_ARCHIVE_OVERRIDE"
    [[ ! -L "$GI_ARCHIVE_OVERRIDE" ]] || gi_die 'el archivo indicado no puede ser un symlink'
    GI_ARCHIVE="$(realpath -- "$GI_ARCHIVE_OVERRIDE")"; return 0
  fi
  while IFS= read -r directory; do
    [[ -d "$directory" ]] || continue
    candidate="$directory/$GI_ARCHIVE_NAME"
    if [[ -f "$candidate" && ! -L "$candidate" ]]; then GI_ARCHIVE="$(realpath -- "$candidate")"; return 0; fi
  done < <(gi_download_dirs)
  return 1
}

gi_checksum() { if [[ "$GI_CHECKSUM_ALGO" == 'sha512' ]]; then sha512sum -- "$1" | awk '{print $1}'; else md5sum -- "$1" | awk '{print $1}'; fi; }

gi_validate_zip() {
  local archive="$1" entry link_target resolved
  [[ "$(basename -- "$archive")" == "$GI_ARCHIVE_NAME" ]] || gi_die "nombre de archivo no admitido; se esperaba $GI_ARCHIVE_NAME"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" != /* ]] || gi_die "ZIP con ruta absoluta: $entry"
    [[ "$entry" != *'..'* ]] || gi_die "ZIP con posible traversal: $entry"
    case "$entry" in *\\*) gi_die "ZIP con separador no permitido: $entry";; esac
  done < <(zipinfo -1 -- "$archive")
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    link_target="$(unzip -p -- "$archive" "$entry")"
    [[ -n "$link_target" && "$link_target" != /* ]] || gi_die "symlink inseguro en ZIP: $entry"
    case "$link_target" in
      *..*|*\\*) gi_die "symlink inseguro en ZIP: $entry";;
    esac
    resolved="$(realpath -m -- "$(dirname -- "$entry")/$link_target")"
    case "$resolved" in
      "$GI_REQUIRED_ROOT"/*) ;;
      *) gi_die "symlink fuera de la raíz del juego: $entry";;
    esac
  done < <(zipinfo -l -- "$archive" | awk '$1 ~ /^l[rwx-]{9}$/ {for (i=12; i<=NF; i++) {printf "%s%s", $i, (i<NF ? OFS : "")} print ""}')
  if zipinfo -l -- "$archive" | awk '$1 ~ /^[bcp][rwx-]{9}$/ {bad=1} END {exit bad}'; then :; else gi_die 'el ZIP contiene archivos especiales'; fi
  unzip -tqq -- "$archive" >/dev/null || gi_die 'la integridad del ZIP no es válida'
  unzip -Z1 -- "$archive" | awk -v root="$GI_REQUIRED_ROOT/" 'index($0, root) == 1 {found=1} END {exit !found}' || gi_die "falta el directorio raíz esperado: $GI_REQUIRED_ROOT/"
  unzip -Z1 -- "$archive" | grep -Fxe "$GI_REQUIRED_ROOT/$GI_RUN_RELATIVE" >/dev/null || gi_die "falta el ejecutable esperado: $GI_REQUIRED_ROOT/$GI_RUN_RELATIVE"
}

gi_verify_archive() {
  [[ -n "$GI_ARCHIVE" ]] || gi_die 'no se ha seleccionado un archivo'
  gi_validate_zip "$GI_ARCHIVE"
  [[ "$(gi_checksum "$GI_ARCHIVE")" == "$GI_EXPECTED_CHECKSUM" ]] || gi_die "checksum $GI_CHECKSUM_ALGO incorrecto para $(basename -- "$GI_ARCHIVE")"
  gi_ok "archivo verificado: $(basename -- "$GI_ARCHIVE") ($GI_CHECKSUM_ALGO)"
}

gi_download_archive() {
  local destination directory tool
  tool="$(gi_download_tool || true)"; [[ -n "$tool" ]] || gi_die 'falta curl o wget para descargar el archivo oficial'
  directory="$(while IFS= read -r candidate; do [[ -d "$candidate" ]] && { printf '%s' "$candidate"; break; }; done < <(gi_download_dirs))"
  if [[ -z "$directory" ]]; then directory="$HOME/Downloads"; mkdir -p -- "$directory"; fi
  destination="$directory/$GI_ARCHIVE_NAME"
  [[ ! -L "$destination" ]] || gi_die "la ruta de descarga es un symlink y no se sobrescribirá: $destination"
  gi_info "descargando $GI_GAME_NAME $GI_VERSION desde la fuente oficial"
  if [[ "$tool" == 'curl' ]]; then curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --silent --show-error --output "$destination" "$GI_DOWNLOAD_URL"; else wget --https-only --quiet --show-progress --output-document="$destination" "$GI_DOWNLOAD_URL"; fi
  [[ -s "$destination" ]] || gi_die 'la descarga produjo un archivo vacío'
  GI_ARCHIVE="$(realpath -- "$destination")"
}

gi_package_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
gi_package_candidate() { local candidate; candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"; [[ -n "$candidate" && "$candidate" != '(none)' ]]; }

gi_resolve_packages() {
  GI_MISSING_PACKAGES=()
  local alternatives package found
  for alternatives in "${GI_REQUIRED_PACKAGES[@]}"; do
    found='no'; IFS='|' read -r -a package_options <<< "$alternatives"
    for package in "${package_options[@]}"; do if gi_package_installed "$package"; then found='yes'; break; fi; done
    [[ "$found" == 'yes' ]] && continue
    found='no'; for package in "${package_options[@]}"; do if gi_package_candidate "$package"; then GI_MISSING_PACKAGES+=("$package"); found='yes'; break; fi; done
    [[ "$found" == 'yes' ]] || gi_warn "sin candidato APT detectado para: $alternatives"
  done
}

gi_show_graphics() {
  if [[ -n "${DISPLAY:-}" ]] && command -v glxinfo >/dev/null 2>&1; then glxinfo -B 2>/dev/null | awk -F: '/OpenGL vendor string|OpenGL renderer string|OpenGL version string/ {gsub(/^[[:space:]]+/, "", $2); print "opengl=" $2}'; else printf '%s\n' 'opengl=pendiente (requiere sesión gráfica DISPLAY)'; fi
}

gi_check_ldd() {
  local root="$1" elf='' candidate
  if [[ -n "${GI_BINARY_RELATIVE:-}" && -f "$root/$GI_BINARY_RELATIVE" ]]; then elf="$root/$GI_BINARY_RELATIVE"; else while IFS= read -r candidate; do if file --brief -- "$candidate" | grep -q 'ELF 64-bit.*x86-64'; then elf="$candidate"; break; fi; done < <(find "$root" -type f -perm -u+x -print); fi
  [[ -n "$elf" ]] || gi_die 'no se encontró un ejecutable ELF x86-64 para revisar dependencias'
  if ldd -- "$elf" 2>&1 | grep -q 'not found'; then gi_warn "dependencias faltantes para $(basename -- "$elf")"; ldd -- "$elf" 2>&1 | grep 'not found' || true; return 1; fi
  gi_ok "dependencias ELF resueltas: $(basename -- "$elf")"
}

gi_write_file_atomically() {
  local destination="$1" content="$2" directory temporary
  directory="$(dirname -- "$destination")"; mkdir -p -- "$directory"
  if [[ -e "$destination" || -L "$destination" ]]; then grep -Fq "Rafex managed: $GI_SLUG" -- "$destination" 2>/dev/null || gi_die "se niega a sobrescribir archivo no administrado: $destination"; fi
  temporary="$(mktemp "$directory/.rafex-${GI_SLUG}.XXXXXX")"; printf '%s\n' "$content" > "$temporary"; chmod 0755 "$temporary"; mv -f -- "$temporary" "$destination"
}

gi_install_launchers() {
  local launcher="$HOME/.local/bin/$GI_LAUNCHER_NAME" desktop="$HOME/.local/share/applications/rafex-${GI_SLUG}.desktop" game_dir_q launcher_q
  printf -v game_dir_q '%q' "$GI_INSTALL_DIR"; printf -v launcher_q '%q' "$launcher"
  gi_write_file_atomically "$launcher" "#!/usr/bin/env bash
# Rafex managed: $GI_SLUG
set -Eeuo pipefail
GAME_DIR=$game_dir_q
exec \"\$GAME_DIR/$GI_RUN_RELATIVE\" \"\$@\""
  gi_write_file_atomically "$desktop" "[Desktop Entry]
# Rafex managed: $GI_SLUG
Type=Application
Name=$GI_DESKTOP_NAME
Comment=$GI_GAME_NAME $GI_VERSION
Exec=$launcher_q
Path=$GI_INSTALL_DIR
Terminal=false
Categories=Game;"
  gi_ok "lanzador instalado: $launcher"; gi_ok "entrada de aplicaciones instalada: $desktop"
}

gi_write_metadata() {
  local temporary checksum; checksum="$(gi_checksum "$GI_ARCHIVE")"; mkdir -p -- "$GI_STATE_DIR"; temporary="$(mktemp "$GI_STATE_DIR/.install.XXXXXX")"
  cat > "$temporary" <<EOF
game=$GI_SLUG
version=$GI_VERSION
archive=$(basename -- "$GI_ARCHIVE")
checksum_algorithm=$GI_CHECKSUM_ALGO
checksum=$checksum
source=$GI_DOWNLOAD_URL
install_dir=$GI_INSTALL_DIR
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  mv -f -- "$temporary" "$GI_STATE_DIR/install.tsv"
}

gi_prepare_stage() {
  mkdir -p -- "$GI_GAMES_DIR"; GI_STAGE_DIR="$(mktemp -d "$GI_GAMES_DIR/.rafex-${GI_SLUG}.XXXXXX")"; unzip -q -- "$GI_ARCHIVE" -d "$GI_STAGE_DIR"
  [[ -d "$GI_STAGE_DIR/$GI_REQUIRED_ROOT" ]] || gi_die 'la extracción no produjo el directorio esperado'
  [[ -f "$GI_STAGE_DIR/$GI_REQUIRED_ROOT/$GI_RUN_RELATIVE" ]] || gi_die 'falta el lanzador después de extraer'
  [[ -x "$GI_STAGE_DIR/$GI_REQUIRED_ROOT/$GI_RUN_RELATIVE" ]] || chmod u+x "$GI_STAGE_DIR/$GI_REQUIRED_ROOT/$GI_RUN_RELATIVE"
  while IFS= read -r link; do
    resolved="$(realpath -m -- "$link")"
    case "$resolved" in
      "$GI_STAGE_DIR/$GI_REQUIRED_ROOT"/*) ;;
      *) gi_die "symlink extraído fuera del juego: $link";;
    esac
  done < <(find "$GI_STAGE_DIR/$GI_REQUIRED_ROOT" -type l -print)
  gi_check_ldd "$GI_STAGE_DIR/$GI_REQUIRED_ROOT"
}

gi_backup_existing() {
  local timestamp backup_dir; timestamp="$(date -u +%Y%m%dT%H%M%SZ)"; backup_dir="$GI_STATE_DIR/backups/$timestamp"; mkdir -p -- "$backup_dir"; mv -- "$GI_INSTALL_DIR" "$backup_dir/payload"; [[ ! -e "$GI_STATE_DIR/install.tsv" ]] || mv -- "$GI_STATE_DIR/install.tsv" "$backup_dir/install.tsv"; gi_info "respaldo administrado creado: $backup_dir"
}

gi_publish() {
  local staged_root="$GI_STAGE_DIR/$GI_REQUIRED_ROOT"
  if [[ -e "$GI_INSTALL_DIR" || -L "$GI_INSTALL_DIR" ]]; then [[ -r "$GI_STATE_DIR/install.tsv" ]] || gi_die "la instalación existente no está administrada: $GI_INSTALL_DIR"; [[ "$GI_UPGRADE" == 'yes' ]] || gi_die 'la instalación ya existe; usa --upgrade para reemplazarla'; gi_backup_existing; fi
  mv -- "$staged_root" "$GI_INSTALL_DIR"; gi_write_metadata; gi_install_launchers; gi_ok "$GI_GAME_NAME $GI_VERSION instalado en $GI_INSTALL_DIR"
}

gi_show_status() {
  echo -e "${BOLD}${CYAN}═══ $GI_GAME_NAME $GI_VERSION ═══${RESET}"; printf 'version=%s\narchive=%s\nsource=%s\ninstall_dir=%s\n' "$GI_VERSION" "$GI_ARCHIVE_NAME" "$GI_DOWNLOAD_URL" "$GI_INSTALL_DIR"
  if [[ -r "$GI_STATE_DIR/install.tsv" ]]; then gi_ok 'instalación administrada presente'; sed 's/^checksum=.*/checksum=<oculto en status breve>/' "$GI_STATE_DIR/install.tsv"; else printf '%s\n' 'managed_install=absent'; fi
  gi_resolve_packages || true; [[ ${#GI_MISSING_PACKAGES[@]} -eq 0 ]] && gi_ok 'dependencias Debian requeridas presentes o resueltas' || printf 'missing_packages=%s\n' "${GI_MISSING_PACKAGES[*]}"; gi_show_graphics
}

gi_show_check() {
  echo -e "${BOLD}${CYAN}═══ Check $GI_GAME_NAME $GI_VERSION ═══${RESET}"
  if gi_find_archive; then printf 'archive_path=%s\n' "$GI_ARCHIVE"; gi_verify_archive; else gi_warn "no se encontró $GI_ARCHIVE_NAME en Descargas; --apply lo descargará desde la fuente oficial"; fi
  gi_resolve_packages || true; [[ ${#GI_MISSING_PACKAGES[@]} -eq 0 ]] && gi_ok 'dependencias Debian requeridas presentes o resolubles' || printf 'missing_packages=%s\n' "${GI_MISSING_PACKAGES[*]}"; gi_show_graphics
}

gi_show_plan() {
  echo -e "${BOLD}${CYAN}═══ Plan $GI_GAME_NAME $GI_VERSION ═══${RESET}"; if gi_find_archive; then gi_info "usar archivo local: $GI_ARCHIVE"; else gi_info "descargar $GI_ARCHIVE_NAME desde $GI_DOWNLOAD_URL"; fi; gi_info "verificar $GI_CHECKSUM_ALGO: $GI_EXPECTED_CHECKSUM"; gi_info 'validar ZIP, impedir traversal/symlinks y comprobar ELF x86-64'; gi_info "instalar dependencias Debian faltantes: ${GI_REQUIRED_PACKAGES[*]}"; gi_info "publicar atómicamente en $GI_INSTALL_DIR"; gi_info 'crear lanzador de usuario y entrada .desktop; no habrá autostart'; [[ "$GI_UPGRADE" == 'yes' ]] && gi_info 'se permite upgrade con respaldo administrado'; gi_info 'no se escribirá nada en modo plan'
}

gi_rollback() {
  local latest backup_dir current_dir; latest="$(find "$GI_STATE_DIR/backups" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort | tail -1)"; [[ -n "$latest" && -d "$latest/payload" ]] || gi_die 'no existe un respaldo administrado para rollback'; mkdir -p -- "$GI_STATE_DIR/rollback-current"; if [[ -e "$GI_INSTALL_DIR" || -L "$GI_INSTALL_DIR" ]]; then current_dir="$GI_STATE_DIR/rollback-current/$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p -- "$current_dir"; mv -- "$GI_INSTALL_DIR" "$current_dir/payload"; fi; mv -- "$latest/payload" "$GI_INSTALL_DIR"; [[ ! -f "$latest/install.tsv" ]] || mv -- "$latest/install.tsv" "$GI_STATE_DIR/install.tsv"; gi_ok "rollback restaurado desde $latest"; gi_install_launchers
}

gi_main() {
  gi_parse_args "$@"; gi_require_base
  case "$GI_ACTION" in
    status) gi_show_status;; rollback) gi_rollback;; check) gi_show_check;; plan) gi_show_plan;;
    apply)
      if ! gi_find_archive; then gi_download_archive; fi
      gi_verify_archive; gi_resolve_packages
      if [[ ${#GI_MISSING_PACKAGES[@]} -gt 0 ]]; then gi_info "instalando dependencias: ${GI_MISSING_PACKAGES[*]}"; sudo apt-get update; sudo apt-get install -y --no-install-recommends "${GI_MISSING_PACKAGES[@]}"; fi
      gi_prepare_stage; gi_publish;;
    *) gi_die "acción no soportada: $GI_ACTION";;
  esac
}
