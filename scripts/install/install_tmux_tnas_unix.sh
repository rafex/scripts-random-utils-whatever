#!/usr/bin/env bash
# v1.0.0 - Compila tmux estático ARM64 en Podman remoto e instala en TNAS.
set -Eeuo pipefail
umask 077

ACTION='build'
readonly VERSION='3.7c'
readonly BUILDER_IMAGE='docker.io/library/alpine@sha256:24bb3511a0db7b5114a4aee033c65a8a4148f39b7b80a398e548546db967a36f'
readonly PODMAN_CONNECTION="${PODMAN_CONNECTION:-debian-server-wifi}"
readonly TNAS_SSH_TARGET="${TNAS_SSH_TARGET:-admin@192.168.3.56}"
readonly TNAS_SSH_PORT="${TNAS_SSH_PORT:-9222}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly OUTPUT_DIR="${TMUX_TNAS_OUTPUT_DIR:-${REPO_ROOT}/dist}"
readonly OUTPUT_BIN="${OUTPUT_DIR}/tmux-${VERSION}-linux-arm64"
TEMP_DIR=''

info() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
die() { printf '✗ ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  install_tmux_tnas_unix.sh [--build|--install]

Compila tmux estático para Linux ARM64 con el Podman remoto configurado y lo
deja en dist/. --install además lo copia a /home/admin/bin/tmux en el TNAS.

Variables:
  PODMAN_CONNECTION   Conexión Podman remota (default: debian-server-wifi)
  TNAS_SSH_TARGET     Destino SSH (default: admin@192.168.3.56)
  TNAS_SSH_PORT       Puerto SSH (default: 9222)
  TMUX_TNAS_OUTPUT_DIR Directorio local para el binario (default: dist/)
EOF
}

parse_args() {
  [[ $# -le 1 ]] || die 'selecciona una sola acción'
  if [[ $# -eq 1 ]]; then
    case "$1" in
      --build) ACTION='build' ;;
      --install) ACTION='install' ;;
      --help|-h) usage; exit 0 ;;
      *) die "opción desconocida: $1" ;;
    esac
  fi
}

require_tools() {
  for command_name in podman ssh scp mktemp install; do
    command -v "$command_name" >/dev/null 2>&1 || die "falta el comando: $command_name"
  done
  [[ "$TNAS_SSH_PORT" =~ ^[0-9]+$ ]] || die 'TNAS_SSH_PORT debe ser numérico'
  podman --connection "$PODMAN_CONNECTION" info >/dev/null \
    || die "no está disponible la conexión Podman '$PODMAN_CONNECTION'"
}

build_tmux() {
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tmux-tos-build.XXXXXX")"
  mkdir -p -- "$OUTPUT_DIR"
  info "Compilando tmux ${VERSION} para Linux ARM64 en Podman '$PODMAN_CONNECTION'."

  podman --connection "$PODMAN_CONNECTION" run --rm --arch arm64 -i "$BUILDER_IMAGE" sh -s \
    > "${TEMP_DIR}/tmux" <<'BUILD_IN_CONTAINER'
set -eu
exec 3>&1
exec 1>&2

apk add --no-cache build-base bison ca-certificates curl file pkgconf tar xz
mkdir -p /tmp/src /opt/tmux-deps /opt/tmux
cd /tmp/src

curl --fail --location --silent --show-error \
  https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz \
  -o libevent.tar.gz
printf '%s  %s\n' \
  92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb \
  libevent.tar.gz | sha256sum -c -
tar -xzf libevent.tar.gz
cd /tmp/src/libevent-2.1.12-stable
./configure --prefix=/opt/tmux-deps --disable-shared --enable-static --disable-openssl
make -j2
make install

cd /tmp/src
curl --fail --location --silent --show-error \
  https://invisible-mirror.net/archives/ncurses/ncurses-6.5.tar.gz \
  -o ncurses.tar.gz
printf '%s  %s\n' \
  136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6 \
  ncurses.tar.gz | sha256sum -c -
tar -xzf ncurses.tar.gz
cd /tmp/src/ncurses-6.5
./configure \
  --prefix=/opt/tmux-deps \
  --without-shared \
  --with-normal \
  --without-debug \
  --without-ada \
  --without-cxx \
  --without-progs \
  --without-tests \
  --without-manpages \
  --disable-db-install \
  --enable-widec \
  --enable-pc-files \
  --with-pkg-config-libdir=/opt/tmux-deps/lib/pkgconfig
make -j2
make install

cd /tmp/src
curl --fail --location --silent --show-error \
  https://github.com/tmux/tmux/releases/download/3.7c/tmux-3.7c.tar.gz \
  -o tmux.tar.gz
printf '%s  %s\n' \
  7c60cae9a0e25288e2e24750aafc9e8800fc7fd4555e447e1b29ee4201cfb3bf \
  tmux.tar.gz | sha256sum -c -
tar -xzf tmux.tar.gz
cd /tmp/src/tmux-3.7c
PKG_CONFIG_PATH=/opt/tmux-deps/lib/pkgconfig \
CPPFLAGS=-I/opt/tmux-deps/include \
LDFLAGS='-L/opt/tmux-deps/lib -static' \
  ./configure --prefix=/opt/tmux --enable-static
make -j2
install -m 0755 tmux /opt/tmux/tmux

test "$(uname -m)" = aarch64
test "$(/opt/tmux/tmux -V)" = 'tmux 3.7c'
file /opt/tmux/tmux | grep -q 'statically linked'
cat /opt/tmux/tmux >&3
BUILD_IN_CONTAINER

  [[ -s "${TEMP_DIR}/tmux" ]] || die 'la compilación no produjo un binario'
  file "${TEMP_DIR}/tmux" | grep -q 'statically linked' \
    || die 'el resultado no está enlazado estáticamente'
  install -m 0755 -- "${TEMP_DIR}/tmux" "${OUTPUT_BIN}.tmp"
  mv -f -- "${OUTPUT_BIN}.tmp" "$OUTPUT_BIN"
  ok "Binario generado: $OUTPUT_BIN"
}

install_tmux() {
  [[ -x "$OUTPUT_BIN" ]] || die "primero compila el binario: $OUTPUT_BIN"
  info "Instalando tmux en ${TNAS_SSH_TARGET}:/home/admin/bin/tmux."
  ssh -p "$TNAS_SSH_PORT" "$TNAS_SSH_TARGET" \
    'mkdir -p /home/admin/bin && chmod 700 /home/admin/bin'
  scp -P "$TNAS_SSH_PORT" -- "$OUTPUT_BIN" \
    "${TNAS_SSH_TARGET}:/home/admin/bin/tmux.upload.$$"
  ssh -p "$TNAS_SSH_PORT" "$TNAS_SSH_TARGET" \
    'set -eu; if [ -e /home/admin/bin/tmux ]; then cp -p /home/admin/bin/tmux "/home/admin/bin/tmux.backup.$(date +%Y%m%d%H%M%S)"; fi; mv "/home/admin/bin/tmux.upload.'"$$"'" /home/admin/bin/tmux; chmod 755 /home/admin/bin/tmux; /home/admin/bin/tmux -V'
  ok 'tmux quedó instalado en el espacio del usuario admin.'
}

main() {
  parse_args "$@"
  require_tools
  if [[ "$ACTION" == build || ! -x "$OUTPUT_BIN" ]]; then
    build_tmux
  else
    info "Reutilizando el binario ya compilado: $OUTPUT_BIN"
  fi
  if [[ "$ACTION" == install ]]; then
    install_tmux
  fi
}

main "$@"
