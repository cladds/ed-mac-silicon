#!/usr/bin/env bash
# 02-create-ed-prefix.sh - build a clean Wine prefix for Elite Dangerous.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

KEY="02-create-ed-prefix"
if skip_if_done "$KEY"; then
  exit 0
fi

# Load env (ED_PREFIX, WINEARCH, etc.).
set -a
# shellcheck source=../config/ed-launch.env
source "$REPO_ROOT/config/ed-launch.env"
set +a

WINE_BIN="$(require_wine)"
WINEPREFIX="$ED_PREFIX"
export WINEPREFIX WINEARCH WINE="$WINE_BIN"

info "ED prefix root: $ED_PREFIX"
mkdir -p "$(dirname "$ED_PREFIX")"

# Initialise the prefix if it does not already look initialised.
if [[ ! -f "$ED_PREFIX/system.reg" ]]; then
  info "initialising 64-bit Wine prefix (this opens a few Wine dialogs; let them run)..."
  # wineboot under GPTK often exits non-zero from harmless post-init noise
  # (typically the Wine Mono installer can't find its MSI). Tolerate that
  # and verify by checking that system.reg ends up on disk.
  "$WINE_BIN" wineboot --init || warn "wineboot exited non-zero; verifying prefix state..."
  "$WINE_BIN" wineserver -w || true
  if [[ ! -f "$ED_PREFIX/system.reg" ]]; then
    err "wineboot did not produce $ED_PREFIX/system.reg; the prefix was not created"
    exit 1
  fi
  ok "prefix initialised"
else
  ok "prefix already initialised"
fi

# Install fonts + VC++ runtime that ED + most launchers expect.
# winetricks is idempotent; it skips already-present components quickly.
info "installing winetricks components: corefonts, vcrun2019, dxvk_nvapi (no-op safety)..."
run winetricks -q corefonts vcrun2019 || warn "winetricks reported errors; check the log"

# ----- Steam installer -----
STEAM_INSTALLER="$SETUP_ROOT/cache/SteamSetup.exe"
if [[ ! -f "$STEAM_INSTALLER" ]]; then
  info "downloading SteamSetup.exe..."
  mkdir -p "$(dirname "$STEAM_INSTALLER")"
  run curl -fsSL -o "$STEAM_INSTALLER" \
    "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
fi

# Only run the installer if Steam is not already inside the prefix.
STEAM_EXE="$ED_PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
if [[ ! -f "$STEAM_EXE" ]]; then
  info "running Steam installer inside the prefix..."
  info "click through the installer; do NOT log in yet (that happens in 03-install-ed.sh)."
  # The Steam (NSIS) installer often exits non-zero from a post-install
  # auto-launch step under Wine ("ShellExecuteEx failed: Environment variable
  # not found"). The install itself still completes; we verify by checking
  # for steam.exe afterward.
  "$WINE_BIN" "$STEAM_INSTALLER" /S || warn "Steam installer exited non-zero; verifying install..."
  "$WINE_BIN" wineserver -w || true
else
  ok "Steam already installed in prefix"
fi

if [[ ! -f "$STEAM_EXE" ]]; then
  err "Steam installer finished but steam.exe is missing at: $STEAM_EXE"
  err "open the prefix and inspect: $ED_PREFIX"
  exit 1
fi

run mark_done "$KEY"
ok "ED prefix ready at: $ED_PREFIX"
ok "next: scripts/03-install-ed.sh (interactive Steam login + ED install)"
