#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GI_GAME_NAME='Urban Terror'; GI_SLUG='urban-terror'; GI_VERSION='4.3.4'; GI_ARCHIVE_NAME='UrbanTerror434_full.zip'
GI_DOWNLOAD_URL='https://mirror2.urbanterror.info/UrbanTerror434_full.zip'; GI_INSTALL_DIR="${HOME}/Games/UrbanTerror"; GI_REQUIRED_ROOT='UrbanTerror43'; GI_RUN_RELATIVE='Quake3-UrT.x86_64'; GI_BINARY_RELATIVE='Quake3-UrT.x86_64'
GI_DESKTOP_NAME='Urban Terror'; GI_LAUNCHER_NAME='urban-terror'; GI_CHECKSUM_ALGO='md5'; GI_EXPECTED_CHECKSUM='9bf7f0092161391697d24f6b004a6c6b'
GI_REQUIRED_PACKAGES=('libc6' 'libgl1' 'libgl1-mesa-dri' 'libx11-6' 'libxext6' 'libxrandr2' 'libxi6' 'libxcursor1' 'libxinerama1' 'libxxf86vm1' 'libasound2t64|libasound2' 'zlib1g' 'libfreetype6')
# shellcheck source=../lib/game_install_linux.sh
. "$SCRIPT_DIR/../lib/game_install_linux.sh"
gi_main "$@"
