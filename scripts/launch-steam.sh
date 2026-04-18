#!/usr/bin/env bash
# launch-steam.sh - open Steam inside the ED prefix with the CEF flags that
# work around steamwebhelper crashes on Apple Silicon. Use this when 03-install-ed.sh
# has already been done once but you need to reopen Steam (e.g. to install a new
# DLC, verify files, or re-download the game).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

set -a
# shellcheck source=../config/ed-launch.env
source "$REPO_ROOT/config/ed-launch.env"
set +a

WINE_BIN="$(require_wine)"
export WINEPREFIX="$ED_PREFIX" WINEARCH WINE="$WINE_BIN"

STEAM_EXE="$ED_PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
if [[ ! -f "$STEAM_EXE" ]]; then
  err "Steam not installed in prefix. Run scripts/02-create-ed-prefix.sh first."
  exit 1
fi

info "launching Steam with CEF workarounds for Apple Silicon..."
exec "$WINE_BIN" "$STEAM_EXE" \
  -cef-disable-gpu \
  -cef-disable-gpu-compositing \
  -no-cef-sandbox
