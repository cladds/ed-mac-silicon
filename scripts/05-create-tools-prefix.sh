#!/usr/bin/env bash
# 05-create-tools-prefix.sh - separate prefix for EDDiscovery / EDEngineer.
# EDMarketConnector has a native macOS build; we install that via brew instead.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

KEY="05-create-tools-prefix"
if skip_if_done "$KEY"; then
  exit 0
fi

set -a
# shellcheck source=../config/ed-launch.env
source "$REPO_ROOT/config/ed-launch.env"
set +a

WINE_BIN="$(require_wine)"
export WINEPREFIX="$TOOLS_PREFIX" WINEARCH WINE="$WINE_BIN"

info "tools prefix root: $TOOLS_PREFIX"
mkdir -p "$(dirname "$TOOLS_PREFIX")"

# ----- prefix init -----
if [[ ! -f "$TOOLS_PREFIX/system.reg" ]]; then
  info "initialising tools prefix (separate from ED, so a borked tool update can't kill the game)..."
  run "$WINE_BIN" wineboot --init
  run "$WINE_BIN" wineserver -w
else
  ok "tools prefix already initialised"
fi

# ----- .NET 4.7.2 (EDDiscovery dependency) -----
info "installing .NET Framework 4.7.2 + corefonts via winetricks (slow; expect 5-15 min)..."
run winetricks -q corefonts dotnet472 || warn "winetricks dotnet472 reported errors; investigate the log"

# ----- EDMarketConnector (native macOS build, preferred) -----
if ! command -v brew >/dev/null 2>&1; then
  warn "brew missing; skipping EDMC native install"
elif brew list --cask edmarketconnector >/dev/null 2>&1; then
  ok "EDMarketConnector already installed (native)"
else
  info "installing EDMarketConnector via Homebrew cask (native macOS build)..."
  if ! run brew install --cask edmarketconnector; then
    warn "brew cask edmarketconnector failed; install manually from"
    warn "  https://github.com/EDCD/EDMarketConnector/releases"
  fi
fi

cat <<EOF
${C_INFO}---------------------------------------------------------------${C_RESET}
Tools prefix ready at: $TOOLS_PREFIX

Manual installs (Wine side):
  EDDiscovery  -> https://github.com/EDDiscovery/EDDiscovery/releases
                  Grab the *Portable* zip (avoids the MSI), unzip into
                  $TOOLS_PREFIX/drive_c/Program\\ Files/EDDiscovery
  EDEngineer   -> https://github.com/msarilar/EDEngineer/releases
                  Same idea: portable zip into Program Files.

Then use scripts/launch-eddiscovery.sh.

EDMarketConnector: use the native app (now in /Applications), not the
Windows version. It writes to the same Frontier journal directory inside
the ED prefix, so ED -> EDMC -> Inara still works.
${C_INFO}---------------------------------------------------------------${C_RESET}
EOF

run mark_done "$KEY"
ok "tools prefix complete"
