#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GI_GAME_NAME='Xonotic'; GI_SLUG='xonotic'; GI_VERSION='0.8.6'; GI_ARCHIVE_NAME='xonotic-0.8.6.zip'
GI_DOWNLOAD_URL='https://dl.xonotic.org/xonotic-0.8.6.zip'; GI_INSTALL_DIR="${HOME}/Games/Xonotic"; GI_REQUIRED_ROOT='Xonotic'; GI_RUN_RELATIVE='xonotic-linux-glx.sh'; GI_BINARY_RELATIVE='xonotic-linux64-glx'
GI_DESKTOP_NAME='Xonotic'; GI_LAUNCHER_NAME='xonotic'; GI_CHECKSUM_ALGO='sha512'
GI_EXPECTED_CHECKSUM='cb39879e96f19abb2877588c2d50c5d3e64dd68153bec3dd1bebedf4d765e506afa419c28381d7005aed664cb1a042571c132b5b319e4308cab67745d996c2a6'
GI_REQUIRED_PACKAGES=('libc6' 'libgl1' 'libgl1-mesa-dri' 'libx11-6' 'libxext6' 'libxrandr2' 'libxi6' 'libxcursor1' 'libxinerama1' 'libxxf86vm1' 'libsdl2-2.0-0' 'libvorbisfile3' 'libcurl4t64|libcurl4' 'libpng16-16t64|libpng16-16' 'libopenal1' 'zlib1g' 'libfreetype6')
# shellcheck source=../lib/game_install_linux.sh
. "$SCRIPT_DIR/../lib/game_install_linux.sh"
gi_main "$@"
