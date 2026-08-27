#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prepara una estación de terminal y desarrollo Debian para la ThinkPad.
# Las instalaciones upstream son locales al usuario y no se aceptan
# contraseñas como argumentos, variables de entorno ni archivos.
set -Eeuo pipefail
umask 077

ACTION="check"
STAGE="all"
BODA_VERSION="${BODA_VERSION:-0.2616.0}"
MISE_BIN="${HOME}/.local/bin/mise"
OPENCODE_BIN="${HOME}/.local/bin/opencode"
TMUX_CONFIG="${HOME}/.tmux.conf"
BASHRC="${HOME}/.bashrc"
ALACRITTY_CONFIG="${HOME}/.config/alacritty/alacritty.toml"
STARSHIP_CONFIG="${HOME}/.config/starship.toml"
MISE_CONFIG="${HOME}/.config/mise/config.toml"
BACKUP_STAMP="$(date +%Y%m%d_%H%M%S)"
APT_UPDATED=0
SUDO_VALIDATED=0
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

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
  install_terminal_workstation_linux.sh --check
  install_terminal_workstation_linux.sh --plan [--stage STAGE]
  install_terminal_workstation_linux.sh --apply [--stage STAGE]

Etapas:
  terminal       Bash, Alacritty, tmux y herramientas interactivas
  editor         Neovim y LazyVim con respaldo de la configuración anterior
  runtimes       mise, Node.js LTS y Java Temurin 21
  build-runtimes Maven, Gradle y GraalVM mediante mise (opcional)
  containers      Podman rootless, Buildah y herramientas OCI
  opencode        OpenCode local para el usuario
  all             Todas las etapas recomendadas; build-runtimes es opcional

Opciones:
  --check                Diagnosticar sin modificar nada (default)
  --plan                 Mostrar cambios previstos sin modificar nada
  --dry-run              Alias de --plan
  --apply                Instalar paquetes y configurar archivos
  --stage <etapa>        Etapa a ejecutar (default: all)
  --help                 Mostrar esta ayuda

La contraseña de sudo se solicita únicamente mediante `sudo -v`.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) ACTION="check"; shift ;;
      --plan|--dry-run) ACTION="plan"; shift ;;
      --apply) ACTION="apply"; shift ;;
      --stage)
        [[ $# -ge 2 ]] || die "--stage requiere un valor"
        STAGE="$2"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "argumento desconocido: $1" ;;
    esac
  done
}

require_linux_user() {
  [[ "$(uname -s)" == "Linux" ]] || die "este instalador requiere Linux Debian"
  [[ "$EUID" -ne 0 ]] || die "ejecuta el script como rafex, no como root"
  command -v sudo >/dev/null 2>&1 || die "sudo no está instalado; ejecuta configure_sudo_linux.sh como root"
  case "$STAGE" in
    terminal|editor|runtimes|build-runtimes|containers|opencode|all) ;;
    *) die "etapa no válida: $STAGE" ;;
  esac
}

terminal_packages=(
  bash-completion fzf fd-find bat btop hwatch entr inotify-tools
  ripgrep eza zoxide jq yq tree ncdu duf git-delta lazygit direnv starship
  just tmux mosh kitty-terminfo git curl wget ca-certificates unzip xclip
  shellcheck shfmt build-essential fonts-jetbrains-mono python3-venv pipx
  rustc cargo golang-go
)

editor_packages=(neovim git ripgrep fd-find lazygit gcc make unzip)

runtime_packages=(curl wget ca-certificates tar zstd)

build_runtime_packages=(
  build-essential curl wget ca-certificates unzip
)

container_packages=(
  podman podman-compose buildah skopeo uidmap slirp4netns fuse-overlayfs crun
)

apt_packages_for_stage() {
  case "$1" in
    terminal) printf '%s\n' "${terminal_packages[@]}" ;;
    editor) printf '%s\n' "${editor_packages[@]}" ;;
    runtimes) printf '%s\n' "${runtime_packages[@]}" ;;
    build-runtimes) printf '%s\n' "${build_runtime_packages[@]}" ;;
    containers) printf '%s\n' "${container_packages[@]}" ;;
    opencode) printf '%s\n' curl ca-certificates ;;
    all)
      printf '%s\n' "${terminal_packages[@]}" "${editor_packages[@]}" \
        "${runtime_packages[@]}" "${build_runtime_packages[@]}" \
        "${container_packages[@]}" curl ca-certificates
      ;;
    *) return 1 ;;
  esac | awk '!seen[$0]++'
}

validate_sudo() {
  [[ "$SUDO_VALIDATED" -eq 1 ]] && return 0
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] sudo -v"
    SUDO_VALIDATED=1
    return 0
  fi
  sudo -v
  SUDO_VALIDATED=1
}

install_apt_stage() {
  local stage="$1"
  local packages=()
  mapfile -t packages < <(apt_packages_for_stage "$stage")
  [[ ${#packages[@]} -gt 0 ]] || return 0
  validate_sudo
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] sudo apt-get update"
    info "[plan] sudo apt-get install -y ${packages[*]}"
    return 0
  fi
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    sudo apt-get update
    APT_UPDATED=1
  fi
  sudo apt-get install -y "${packages[@]}"
}

backup_path() {
  local target="$1"
  local backup="${target}.bak.${BACKUP_STAMP}"
  local suffix=1
  [[ -e "$target" || -L "$target" ]] || return 0
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${target}.bak.${BACKUP_STAMP}.${suffix}"
    suffix=$((suffix + 1))
  done
  cp -a "$target" "$backup"
  info "respaldo creado: $backup"
}

move_to_backup() {
  local target="$1"
  local backup="${target}.bak.${BACKUP_STAMP}"
  local suffix=1
  [[ -e "$target" || -L "$target" ]] || return 0
  while [[ -e "$backup" || -L "$backup" ]]; do
    backup="${target}.bak.${BACKUP_STAMP}.${suffix}"
    suffix=$((suffix + 1))
  done
  mv "$target" "$backup"
  info "respaldo creado: $backup"
}

append_managed_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local block="$4"
  local temporary

  if [[ -f "$file" ]] && grep -Fq "$begin" "$file"; then
    ok "configuración ya presente: $file"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] agregar configuración administrada a $file"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  backup_path "$file"
  temporary="$(mktemp)"
  if [[ -f "$file" ]]; then
    cat "$file" > "$temporary"
    chmod --reference="$file" "$temporary"
  fi
  printf '\n%s\n%s\n%s\n' "$begin" "$block" "$end" >> "$temporary"
  mv "$temporary" "$file"
  chmod 600 "$file"
  ok "configuración instalada: $file"
}

bash_block() {
  cat <<'EOF'
# Herramientas terminal-workstation.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if [[ $- == *i* ]]; then
  if [[ -r /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
  fi
  if [[ -r /usr/share/fzf/completion.bash ]]; then
    source /usr/share/fzf/completion.bash
  elif [[ -r /usr/share/doc/fzf/examples/completion.bash ]]; then
    source /usr/share/doc/fzf/examples/completion.bash
  fi
  if [[ -r /usr/share/fzf/key-bindings.bash ]]; then
    source /usr/share/fzf/key-bindings.bash
  elif [[ -r /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.bash
  fi
  if command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    alias fd='fdfind'
  fi
  if command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
    alias bcat='batcat --paging=never'
  elif command -v bat >/dev/null 2>&1; then
    alias bcat='bat --paging=never'
  fi
  if command -v boda >/dev/null 2>&1; then alias bw='boda'; fi
  if command -v hwatch >/dev/null 2>&1; then alias hw='hwatch'; fi
  if command -v eza >/dev/null 2>&1; then
    alias ll='eza -lah --group-directories-first'
    alias la='eza -a --group-directories-first'
  fi
  if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
  fi
  if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
  fi
  if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
  fi
  if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
  fi
fi
EOF
}

starship_config() {
  cat <<'EOF'
# BEGIN terminal-workstation starship
add_newline = false
format = "$directory$git_branch$git_status$nodejs$java$python$line_break$character"

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
format = " [$branch]($style)"

[git_status]
format = "([$all_status$ahead_behind]($style))"

[nodejs]
format = " node [$version]($style)"

[java]
format = " java [$version]($style)"

[python]
format = " py [$version]($style)"

[character]
success_symbol = "[>](bold green) "
error_symbol = "[x](bold red) "
# END terminal-workstation starship
EOF
}

fd_wrapper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec fdfind "$@"
EOF
}

bat_wrapper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if command -v batcat >/dev/null 2>&1; then
  exec batcat "$@"
fi
exec /usr/bin/bat "$@"
EOF
}

bcat_wrapper() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec "$HOME/.local/bin/bat" --paging=never "$@"
EOF
}

install_boda() {
  if command -v boda >/dev/null 2>&1; then
    ok "boda ya está instalado: $(command -v boda)"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] cargo install --locked --version $BODA_VERSION boda"
    return 0
  fi
  command -v cargo >/dev/null 2>&1 || die "cargo es necesario para instalar boda"
  cargo install --locked --version "$BODA_VERSION" boda
  command -v boda >/dev/null 2>&1 || die "boda no quedó instalado en ~/.cargo/bin"
  ok "boda $BODA_VERSION instalado"
}

alacritty_shell_block() {
  cat <<'EOF'
[terminal.shell]
program = "/bin/bash"
args = ["-lc", "exec \"$HOME/.local/bin/start-thinkpad-tmux\""]
EOF
}

tmux_block() {
  cat <<'EOF'
# BEGIN terminal-workstation tmux
set -g default-terminal "tmux-256color"
set -ag terminal-features ",xterm-256color:RGB"
# END terminal-workstation tmux
EOF
}

tmux_launcher() {
  cat <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# Alacritty inicia esta sesión; SSH conserva su comportamiento normal.
if [[ -n "${TMUX:-}" ]]; then
  exec "${SHELL:-/bin/bash}" -l
fi
exec tmux new-session -A -s thinkpad
EOF
}

install_user_executable() {
  local target="$1"
  local content="$2"
  local temporary
  if [[ -x "$target" ]] && cmp -s <(printf '%s\n' "$content") "$target"; then
    ok "ejecutable ya presente: $target"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] instalar ejecutable $target"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  backup_path "$target"
  temporary="$(mktemp)"
  printf '%s\n' "$content" > "$temporary"
  install -m 755 "$temporary" "$target"
  rm -f "$temporary"
  ok "ejecutable instalado: $target"
}

write_starship_config() {
  local content
  content="$(starship_config)"
  if [[ -f "$STARSHIP_CONFIG" ]] && grep -Fq '# BEGIN terminal-workstation starship' "$STARSHIP_CONFIG"; then
    ok "configuración Starship ya presente"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] escribir $STARSHIP_CONFIG"
    return 0
  fi
  mkdir -p "$(dirname "$STARSHIP_CONFIG")"
  backup_path "$STARSHIP_CONFIG"
  printf '%s\n' "$content" > "$STARSHIP_CONFIG"
  chmod 600 "$STARSHIP_CONFIG"
  ok "configuración Starship instalada"
}

update_alacritty() {
  local temporary
  if [[ ! -f "$ALACRITTY_CONFIG" ]]; then
    if [[ "$ACTION" == "plan" ]]; then
      info "[plan] crear $ALACRITTY_CONFIG con fuente 10 y tmux thinkpad"
      return 0
    fi
    mkdir -p "$(dirname "$ALACRITTY_CONFIG")"
    backup_path "$ALACRITTY_CONFIG"
    cat > "$ALACRITTY_CONFIG" <<'EOF'
[env]
TERM = "xterm-256color"
COLORTERM = "truecolor"

[font]
normal = { family = "DejaVu Sans Mono", style = "Regular" }
bold = { family = "DejaVu Sans Mono", style = "Bold" }
italic = { family = "DejaVu Sans Mono", style = "Italic" }
bold_italic = { family = "DejaVu Sans Mono", style = "Bold Italic" }
size = 10

[window]
decorations = "none"
dynamic_title = true

[scrolling]
history = 50000

[selection]
save_to_clipboard = true

# BEGIN terminal-workstation alacritty
[terminal.shell]
program = "/bin/bash"
args = ["-lc", "exec \"$HOME/.local/bin/start-thinkpad-tmux\""]
# END terminal-workstation alacritty
EOF
    chmod 600 "$ALACRITTY_CONFIG"
    ok "configuración Alacritty instalada"
    return 0
  fi

  if grep -Fq '# BEGIN terminal-workstation alacritty' "$ALACRITTY_CONFIG"; then
    ok "lanzador tmux de Alacritty ya presente"
  elif grep -Eq '^\[terminal\.shell\]' "$ALACRITTY_CONFIG"; then
    warn "Alacritty ya tiene [terminal.shell]; no se añadió otra tabla TOML"
  elif [[ "$ACTION" == "plan" ]]; then
    info "[plan] añadir lanzador tmux a $ALACRITTY_CONFIG"
  else
    append_managed_block "$ALACRITTY_CONFIG" \
      '# BEGIN terminal-workstation alacritty' \
      '# END terminal-workstation alacritty' \
      "$(alacritty_shell_block)"
  fi

  if awk '
    /^\[font\]$/ { in_font=1; next }
    /^\[/ { in_font=0 }
    in_font && /^size[[:space:]]*=[[:space:]]*10[[:space:]]*$/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$ALACRITTY_CONFIG"; then
    ok "tamaño de fuente Alacritty ya es 10"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] cambiar tamaño de fuente Alacritty a 10"
    return 0
  fi
  if ! grep -q '^\[font\]$' "$ALACRITTY_CONFIG"; then
    warn "no se encontró [font] en $ALACRITTY_CONFIG; revísalo manualmente"
    return 0
  fi
  backup_path "$ALACRITTY_CONFIG"
  temporary="$(mktemp)"
  awk '
    /^\[font\]$/ { in_font=1 }
    /^\[/ && $0 != "[font]" { in_font=0 }
    in_font && /^size[[:space:]]*=/ && !changed { print "size = 10"; changed=1; next }
    { print }
  ' "$ALACRITTY_CONFIG" > "$temporary"
  chmod --reference="$ALACRITTY_CONFIG" "$temporary"
  mv "$temporary" "$ALACRITTY_CONFIG"
  ok "tamaño de fuente Alacritty ajustado a 10"
}

configure_terminal() {
  install_apt_stage terminal
  install_boda
  install_user_executable "$HOME/.local/bin/start-thinkpad-tmux" "$(tmux_launcher)"
  install_user_executable "$HOME/.local/bin/fd" "$(fd_wrapper)"
  install_user_executable "$HOME/.local/bin/bat" "$(bat_wrapper)"
  install_user_executable "$HOME/.local/bin/bcat" "$(bcat_wrapper)"
  append_managed_block "$BASHRC" \
    '# BEGIN terminal-workstation bash' \
    '# END terminal-workstation bash' \
    "$(bash_block)"
  append_managed_block "$TMUX_CONFIG" \
    '# BEGIN terminal-workstation tmux' \
    '# END terminal-workstation tmux' \
    "$(tmux_block)"
  write_starship_config
  update_alacritty
}

configure_editor() {
  local nvim_config="$HOME/.config/nvim"
  local nvim_data="$HOME/.local/share/nvim"
  local nvim_state="$HOME/.local/state/nvim"
  local nvim_cache="$HOME/.cache/nvim"
  local temporary

  install_apt_stage editor
  if [[ -d "$nvim_config" || -L "$nvim_config" ]]; then
    if [[ "$ACTION" == "plan" ]]; then
      info "[plan] respaldar $nvim_config como ${nvim_config}.bak.$BACKUP_STAMP"
    else
      move_to_backup "$nvim_config"
    fi
  fi
  for path in "$nvim_data" "$nvim_state" "$nvim_cache"; do
    if [[ -e "$path" || -L "$path" ]]; then
      if [[ "$ACTION" == "plan" ]]; then
        info "[plan] respaldar $path como ${path}.bak.$BACKUP_STAMP"
      else
        move_to_backup "$path"
      fi
    fi
  done
  if [[ "$ACTION" != "plan" && ( -e "$nvim_config" || -L "$nvim_config" ) ]]; then
    warn "LazyVim no se instaló porque ~/.config/nvim todavía existe; revisa el respaldo"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] git clone del starter oficial de LazyVim en $nvim_config"
    info "[plan] nvim --headless '+Lazy! sync' '+qa'"
    return 0
  fi
  temporary="$(mktemp -d)"
  git clone --filter=blob:none https://github.com/LazyVim/starter "$temporary/nvim"
  mv "$temporary/nvim" "$nvim_config"
  rm -rf "$temporary"
  rm -rf "$nvim_config/.git"
  nvim --headless '+Lazy! sync' '+qa'
  ok "LazyVim instalado y plugins sincronizados"
}

install_mise() {
  local temporary
  if [[ -x "$MISE_BIN" ]]; then
    ok "mise ya está instalado: $MISE_BIN"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] descargar y verificar el instalador oficial de mise"
    info "[plan] instalar mise en $MISE_BIN"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || die "curl es necesario para instalar mise"
  temporary="$(mktemp)"
  curl --fail --silent --show-error --location https://mise.run -o "$temporary"
  MISE_INSTALL_PATH="$MISE_BIN" MISE_INSTALL_SKIP_IF_EXISTS=1 sh "$temporary"
  rm -f "$temporary"
  [[ -x "$MISE_BIN" ]] || die "mise no quedó instalado en $MISE_BIN"
  ok "mise instalado en $MISE_BIN"
}

configure_mise() {
  install_apt_stage runtimes
  install_mise
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] mise use --global node@lts java@temurin-21"
    return 0
  fi
  mkdir -p "$(dirname "$MISE_CONFIG")"
  "$MISE_BIN" use --global node@lts java@temurin-21
  ok "Node.js LTS y Java Temurin 21 configurados mediante mise"
}

configure_build_runtimes() {
  install_apt_stage build-runtimes
  install_mise
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] mise use --global maven@latest gradle@latest graalvm@latest"
    return 0
  fi
  "$MISE_BIN" use --global maven@latest gradle@latest graalvm@latest
  ok "Maven, Gradle y GraalVM configurados mediante mise"
}

configure_containers() {
  install_apt_stage containers
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] verificar Podman rootless como rafex"
    return 0
  fi
  command -v podman >/dev/null 2>&1 || die "podman no quedó instalado"
  podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || \
    warn "Podman está instalado, pero la información rootless requiere revisar subuid/subgid"
  ok "Podman y herramientas OCI instalados; no se activó ningún daemon privilegiado"
}

install_opencode() {
  local temporary
  if [[ -x "$OPENCODE_BIN" ]]; then
    ok "OpenCode ya está instalado: $OPENCODE_BIN"
    return 0
  fi
  if [[ "$ACTION" == "plan" ]]; then
    info "[plan] descargar el instalador oficial de OpenCode en un temporal"
    info "[plan] instalar OpenCode en $OPENCODE_BIN sin configurar credenciales"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || die "curl es necesario para instalar OpenCode"
  temporary="$(mktemp)"
  curl --fail --silent --show-error --location https://opencode.ai/install -o "$temporary"
  bash "$temporary" --no-modify-path
  rm -f "$temporary"
  if [[ ! -x "$HOME/.opencode/bin/opencode" ]]; then
    warn "El instalador oficial no creó $HOME/.opencode/bin/opencode"
    return 0
  fi
  mkdir -p "$(dirname "$OPENCODE_BIN")"
  backup_path "$OPENCODE_BIN"
  install -m 755 "$HOME/.opencode/bin/opencode" "$OPENCODE_BIN"
  ok "OpenCode instalado sin autenticación"
}

check_commands() {
  local command_name
  echo
  echo -e "${BOLD}${CYAN}═══ Estado estación terminal ═══${RESET}"
  for command_name in fzf fdfind batcat btop hwatch eza zoxide rg jq yq \
    nvim tmux starship mise podman boda opencode; do
    if command -v "$command_name" >/dev/null 2>&1 || \
      [[ -x "$HOME/.local/bin/$command_name" ]] || [[ -x "$HOME/.cargo/bin/$command_name" ]]; then
      printf '%s=available\n' "$command_name"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
  for file in "$BASHRC" "$TMUX_CONFIG" "$ALACRITTY_CONFIG" "$STARSHIP_CONFIG"; do
    if [[ -f "$file" ]]; then
      printf '%s=present\n' "$file"
    else
      printf '%s=missing\n' "$file"
    fi
  done
  if [[ -f "$MISE_CONFIG" ]]; then
    ok "configuración global de mise presente: $MISE_CONFIG"
  fi
}

run_stage() {
  case "$1" in
    terminal) configure_terminal ;;
    editor) configure_editor ;;
    runtimes) configure_mise ;;
    build-runtimes) configure_build_runtimes ;;
    containers) configure_containers ;;
    opencode) install_apt_stage opencode; install_opencode ;;
    all)
      configure_terminal
      configure_editor
      configure_mise
      configure_containers
      install_opencode
      ;;
    *) die "etapa no válida: $1" ;;
  esac
}

main() {
  parse_args "$@"
  require_linux_user
  if [[ "$ACTION" == "check" ]]; then
    check_commands
    exit 0
  fi
  run_stage "$STAGE"
  check_commands
  ok "etapa '$STAGE' completada"
}

main "$@"
