#!/usr/bin/env bash
# 02b-install-ed-via-steamcmd.sh - download Elite Dangerous via SteamCMD
# (Valve's headless command-line client) running under Wine. Use this when
# the Steam GUI's steamwebhelper crashes on Apple Silicon and you can't get
# past the library screen.
#
# Files land in the same path the Steam GUI would use, so min-ed-launcher
# (step 04) finds them with no extra configuration.
#
# Caveat: if your only ED entitlement is a Steam key, ED still wants Steam
# running at launch time to verify the licence. The game might launch fine
# (Steamworks honours steam_appid.txt under some conditions), but if it
# refuses to start with a licence error, you have two fallbacks:
#   a) Run Steam GUI in the background while playing (try `launch-steam.sh`).
#   b) Link your Steam key to a Frontier account at
#      https://user.frontierstore.net (Account -> Add Game Code), then
#      min-ed-launcher will use Frontier auth and Steam is no longer needed.
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

# Per-app sentinel so re-running with a different ED_APP_ID (e.g. Odyssey)
# is not short-circuited by the base game's sentinel.
ED_APP_ID="${ED_APP_ID:-359320}"
KEY="02b-install-ed-via-steamcmd-${ED_APP_ID}"
if skip_if_done "$KEY"; then
  exit 0
fi

require_cmd curl "comes with macOS"
require_cmd unzip "comes with macOS"

WINE_BIN="$(require_wine)"
export WINEPREFIX="$ED_PREFIX" WINEARCH WINE="$WINE_BIN"

if [[ ! -d "$ED_PREFIX" ]]; then
  err "ED prefix missing at: $ED_PREFIX. Run 02-create-ed-prefix.sh first."
  exit 1
fi

# ----- download SteamCMD if missing -----
STEAMCMD_DIR="$ED_PREFIX/drive_c/steamcmd"
STEAMCMD_EXE="$STEAMCMD_DIR/steamcmd.exe"
if [[ ! -f "$STEAMCMD_EXE" ]]; then
  CACHE_ZIP="$SETUP_ROOT/cache/steamcmd.zip"
  if [[ ! -f "$CACHE_ZIP" ]]; then
    info "downloading SteamCMD (Windows version)..."
    mkdir -p "$(dirname "$CACHE_ZIP")"
    run curl -fsSL -o "$CACHE_ZIP" \
      "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"
  fi
  info "extracting SteamCMD into prefix at $STEAMCMD_DIR"
  run mkdir -p "$STEAMCMD_DIR"
  run unzip -oq "$CACHE_ZIP" -d "$STEAMCMD_DIR"
else
  ok "SteamCMD already present at $STEAMCMD_EXE"
fi

# ----- collect Steam credentials interactively -----
# We never store the password; we pass the username on the command line and
# SteamCMD prompts for password + Steam Guard code in its own interactive shell.
STEAM_USER="${STEAM_USER:-}"
if [[ -z "$STEAM_USER" ]]; then
  read -r -p "Steam username: " STEAM_USER
fi
if [[ -z "$STEAM_USER" ]]; then
  err "no Steam username provided"
  exit 1
fi

# ----- install path -----
# Use the same Windows-style path the Steam GUI would use, so min-ed-launcher
# (and the ED_GAME_DIR env in config/ed-launch.env) find the game with no
# further config.
WIN_INSTALL_DIR='C:\Program Files (x86)\Steam\steamapps\common\Elite Dangerous'
# ED_APP_ID was set near the top of the script; 359320 = base game (4.0 /
# Horizons unified client), 1278510 = Odyssey expansion.

cat <<EOF
${C_INFO}---------------------------------------------------------------${C_RESET}
About to launch SteamCMD inside the ED prefix.

What will happen:
  1. SteamCMD prints a banner and prompts for your Steam password.
  2. Then it prompts for a Steam Guard code (mobile app or email).
  3. After login, it downloads Elite Dangerous (app id $ED_APP_ID,
     about 30GB) into:
       $WIN_INSTALL_DIR
     which inside the prefix is:
       $ED_GAME_DIR
  4. SteamCMD exits when the download is verified.

Tips:
  - If you have Steam Guard via the mobile app, approve the login in the
    app instead of typing a code. SteamCMD will detect it and continue.
  - If the download stalls, hit Ctrl+C. Re-running this script resumes.
  - Want Odyssey too? Re-run with: ED_APP_ID=1278510 ./scripts/02b-install-ed-via-steamcmd.sh
${C_INFO}---------------------------------------------------------------${C_RESET}
EOF

read -r -p "Press Enter to launch SteamCMD: " _

if (( DRY_RUN )); then
  info "DRY: $WINE_BIN $STEAMCMD_EXE +force_install_dir $WIN_INSTALL_DIR +login $STEAM_USER +app_update $ED_APP_ID validate +quit"
  exit 0
fi

# Run SteamCMD. We bypass the script's tee'd stdout/stderr by attaching the
# subprocess directly to /dev/tty: SteamCMD draws progress with carriage
# returns and tee buffers those until a newline arrives, hiding the entire
# download. Trade-off: SteamCMD's output won't appear in our log file. That's
# fine because SteamCMD writes its own log to C:\steamcmd\logs\stderr.txt
# inside the prefix.
# `app_update ... validate` is fully resumable; safe to Ctrl+C and re-run.
"$WINE_BIN" "$STEAMCMD_EXE" \
  +force_install_dir "$WIN_INSTALL_DIR" \
  +login "$STEAM_USER" \
  +app_update "$ED_APP_ID" validate \
  +quit \
  </dev/tty >/dev/tty 2>&1 \
  || warn "SteamCMD exited non-zero; checking install state..."

# Verify the game files actually landed.
if [[ ! -d "$ED_GAME_DIR" ]]; then
  err "expected ED files at: $ED_GAME_DIR"
  err "SteamCMD did not produce them. Inspect the log above for the actual cause."
  err "common causes:"
  err "  - wrong Steam Guard code"
  err "  - account does not own app id $ED_APP_ID"
  err "  - Steam side temporary error (try re-running)"
  exit 1
fi

# Sanity check. Steam's ED layout:
#   <ED_GAME_DIR>/EDLaunch.exe                              (Frontier launcher)
#   <ED_GAME_DIR>/Products/elite-dangerous-*-64/EliteDangerous64.exe  (game)
# min-ed-launcher drives EDLaunch.exe, so that's the canonical check.
if [[ ! -f "$ED_GAME_DIR/EDLaunch.exe" ]]; then
  warn "directory exists but EDLaunch.exe is missing"
  warn "the download may be incomplete. Re-run this script to resume."
  exit 1
fi
if ! compgen -G "$ED_GAME_DIR/Products/elite-dangerous-*-64/EliteDangerous64.exe" >/dev/null; then
  warn "EDLaunch.exe present but no Products/*/EliteDangerous64.exe found"
  warn "the download may be incomplete. Re-run this script to resume."
  exit 1
fi

mark_done "$KEY"
ok "ED installed at: $ED_GAME_DIR"
ok "next: scripts/04-install-launcher.sh"
