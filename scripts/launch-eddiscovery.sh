#!/usr/bin/env bash
# launch-eddiscovery.sh - run EDDiscovery from the tools prefix.
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
export WINEPREFIX="$TOOLS_PREFIX" WINEARCH WINE="$WINE_BIN"

# EDDiscovery installs vary; probe the common locations.
EDD_EXE=""
for c in \
  "$TOOLS_PREFIX/drive_c/Program Files/EDDiscovery/EDDiscovery.exe" \
  "$TOOLS_PREFIX/drive_c/Program Files (x86)/EDDiscovery/EDDiscovery.exe"
do
  if [[ -f "$c" ]]; then EDD_EXE="$c"; break; fi
done

if [[ -z "$EDD_EXE" ]]; then
  err "EDDiscovery.exe not found in tools prefix."
  err "Install the portable zip from:"
  err "  https://github.com/EDDiscovery/EDDiscovery/releases"
  err "into:  $TOOLS_PREFIX/drive_c/Program Files/EDDiscovery/"
  exit 1
fi

info "WINEPREFIX=$WINEPREFIX"
info "EDDiscovery: $EDD_EXE"

if (( DRY_RUN )); then
  info "DRY: $WINE_BIN $EDD_EXE"
  exit 0
fi

exec "$WINE_BIN" "$EDD_EXE"
