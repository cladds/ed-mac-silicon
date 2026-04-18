#!/usr/bin/env bash
# 03-install-ed.sh - guide the user through Steam login and ED install.
# This script is interactive on purpose; Steam has 2FA and we never automate that.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

KEY="03-install-ed"
if skip_if_done "$KEY"; then
  exit 0
fi

set -a
# shellcheck source=../config/ed-launch.env
source "$REPO_ROOT/config/ed-launch.env"
set +a

WINE_BIN="$(require_wine)"
export WINEPREFIX="$ED_PREFIX" WINEARCH WINE="$WINE_BIN"

STEAM_EXE="$ED_PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
if [[ ! -f "$STEAM_EXE" ]]; then
  err "Steam not found in prefix. Run scripts/02-create-ed-prefix.sh first."
  exit 1
fi

cat <<EOF
${C_INFO}---------------------------------------------------------------${C_RESET}
About to launch Steam inside the ED prefix.

What to do in the Steam window:
  1. Log in (use Steam Guard / 2FA as normal).
  2. Library -> install Elite Dangerous (and Odyssey + Horizons if listed).
  3. Wait for the download to finish (around 30GB).
  4. Quit Steam (File -> Exit). Do NOT click Play; we use min-ed-launcher.
  5. Come back here and press Enter to mark this step complete.

Heads up: Steam may show a 'Steam needs to update' message on first run.
Let it update.
${C_INFO}---------------------------------------------------------------${C_RESET}
EOF

if (( DRY_RUN )); then
  info "DRY: would launch Steam at $STEAM_EXE"
else
  # Run Steam in the background so this script can prompt for confirmation.
  ( "$WINE_BIN" "$STEAM_EXE" >/dev/null 2>&1 || true ) &
  STEAM_PID=$!
  info "Steam launching (pid $STEAM_PID); window may take 30+ seconds to appear."
fi

read -r -p "Press Enter once ED has finished downloading and you have quit Steam: " _

# Check that ED actually landed where we expect it.
if [[ ! -d "$ED_GAME_DIR" ]]; then
  warn "expected ED at: $ED_GAME_DIR"
  warn "did not find it. If you installed to a different Steam Library folder,"
  warn "edit ED_GAME_DIR in config/ed-launch.env before running 04-install-launcher.sh."
else
  ok "ED game files found: $ED_GAME_DIR"
fi

run mark_done "$KEY"
ok "ED install step complete"
ok "next: scripts/04-install-launcher.sh"
