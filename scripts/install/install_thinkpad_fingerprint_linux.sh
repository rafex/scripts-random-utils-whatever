#!/usr/bin/env bash
# v1.0.0
set -euo pipefail

revision=073e79143d9ecd5832fd3196bf70a51d091382c0
source_sha=aaf8dac3f8c723d11255acebda3bd09a7950cc6ff3869ed2b7e3882a3558b3dd
version='1:1.94.10+vfs0090-1~deb13vfs1'

case "${1:---check}" in
  --help|-h) printf 'Uso: %s [--check|--apply]\n' "${0##*/}"; exit ;;
  --check|--apply) ;;
  *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  printf 'Selecciona una sola opción.\n' >&2
  exit 2
fi

[[ "$(uname -s)" == Linux && "$(dpkg --print-architecture)" == amd64 ]] ||
  { printf 'Se requiere Linux amd64.\n' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == debian && "${VERSION_CODENAME:-}" == forky ]] ||
  { printf 'Este instalador está preparado para Debian Forky.\n' >&2; exit 1; }
if ! lsusb | grep '138a:0090'; then
  printf 'No se detectó el sensor USB Validity 138a:0090.\n' >&2
  exit 1
fi

if [[ "${1:---check}" == --check ]]; then
  dpkg-query -W libfprint-2-2 libfprint-2-vfs0090 fprintd
  fprintd-list "$(id -un)"
  exit
fi

(( EUID != 0 )) || { printf 'Ejecuta como usuario normal con acceso a sudo.\n' >&2; exit 1; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
wrapper="$HOME/.local/bin/enroll-fingerprint"
if [[ -e "$wrapper" || -L "$wrapper" ]]; then
  if [[ -L "$wrapper" ]] || ! cmp -s "$wrapper" "$script_dir/enroll_fingerprint_linux.sh"; then
    printf 'Ya existe un comando distinto en %s.\n' "$wrapper" >&2
    exit 1
  fi
fi

if [[ "$(dpkg-query -W -f='${Status} ${Version}' libfprint-2-vfs0090 2>/dev/null)" != "install ok installed $version" ||
      "$(dpkg-query -W -f='${Status} ${Version}' libfprint-2-2 2>/dev/null)" != "install ok installed $version" ]]; then
  work_dir="$(mktemp -d)"
  trap 'rm -rf -- "$work_dir"' EXIT
  cd -- "$work_dir"
  curl --fail --location --retry 3 \
    "https://codeload.github.com/jamesyc/libfprint/tar.gz/$revision" -o source.tar.gz
  printf '%s  source.tar.gz\n' "$source_sha" | sha256sum -c -
  tar -xzf source.tar.gz

  sudo apt-get install build-essential dpkg-dev debhelper meson ninja-build pkgconf \
    dh-sequence-gir gir1.2-gobject-2.0-dev gir1.2-gio-2.0-dev \
    gtk-doc-tools libcairo-dev libgirepository1.0-dev libglib2.0-dev libgudev-1.0-dev \
    libgusb-dev libnss3-dev libpixman-1-dev libssl-dev python3 python3-cairo python3-gi systemd-dev \
    umockdev libglib2.0-doc libgusb-doc
  dpkg-source -x "libfprint-$revision"/source/*.dsc build
  (
    cd build
    dpkg-checkbuilddeps
    DEB_BUILD_OPTIONS='nocheck parallel=4' dpkg-buildpackage -b -us -uc
  )
  sudo apt-get install ./libfprint-2-2_*_amd64.deb ./libfprint-2-vfs0090_*_amd64.deb
  sudo systemctl restart fprintd
fi

mkdir -p -- "${wrapper%/*}"
install -m 755 -- "$script_dir/enroll_fingerprint_linux.sh" "$wrapper"
fprintd-list "$(id -un)"
