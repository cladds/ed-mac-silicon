#!/usr/bin/env bash
# launch-ed.sh - day-to-day launcher for Elite Dangerous via min-ed-launcher.
#
# Invocation details we learned the hard way:
#   - min-ed-launcher ignores the settings.json sitting next to MinEdLauncher.exe;
#     it only reads %LOCALAPPDATA%\min-ed-launcher\settings.json. So we don't
#     rely on `gameLocation` in settings. Instead we pass the full path to
#     EDLaunch.exe as argv, which short-circuits install-dir discovery.
#   - We run with /frontier <profile> so auth goes directly to Frontier (no
#     Steam client needed at runtime).
#
# Flags:
#   --debug           enable WINEDEBUG=+all (verbose logs)
#   --hud             enable Metal HUD overlay (FPS / VRAM)
#   --no-caffeinate   do not prevent Mac sleep while playing
#   --profile NAME    Frontier credential profile to use (default: "default")
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

USE_CAFFEINATE=1
PROFILE="default"
while (( $# )); do
  case "$1" in
    --debug)         WINEDEBUG="+all"; shift ;;
    --hud)           MTL_HUD_ENABLED=1; shift ;;
    --no-caffeinate) USE_CAFFEINATE=0; shift ;;
    --profile)       PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --dry-run)       shift ;; # handled in _common.sh
    *)               warn "unknown flag: $1"; shift ;;
  esac
done

WINE_BIN="$(require_wine)"
export WINEPREFIX="$ED_PREFIX" WINEARCH WINEDEBUG MTL_HUD_ENABLED WINE="$WINE_BIN"

# min-ed-launcher is a self-contained .NET 8 app; under Wine its HTTPS calls
# go through schannel → GnuTLS/OpenSSL. The Wine prefix has no trusted roots
# by default, so TLS handshakes to Frontier's API fail with 0x80131506. Point
# the TLS libraries at macOS's bundled CA file (shipped at /etc/ssl/cert.pem).
# Covers the three env-var conventions Wine's TLS layers look at.
if [[ -f /etc/ssl/cert.pem ]]; then
  export SSL_CERT_FILE=/etc/ssl/cert.pem
  export CURL_CA_BUNDLE=/etc/ssl/cert.pem
  export GNUTLS_SYSTEM_PRIORITY_FILE=/etc/ssl/cert.pem
fi

# Rosetta 2 can't faithfully emulate some x86 hardware-crypto instructions
# (AES-NI, AVX) that .NET 8's TLS stack uses, which manifests as:
#   rosetta error: unexpectedly need to EmulateForward on a synchronous exception
# Disable all hardware intrinsics so .NET falls back to software crypto.
# Costs perf on the launcher's update check; irrelevant to the game itself.
export DOTNET_EnableHWIntrinsic=0
export COMPlus_EnableHWIntrinsic=0

LAUNCHER_EXE="$MIN_ED_LAUNCHER_DIR/MinEdLauncher.exe"
if [[ ! -f "$LAUNCHER_EXE" ]]; then
  err "min-ed-launcher missing: $LAUNCHER_EXE"
  err "run scripts/04-install-launcher.sh first"
  exit 1
fi

# Windows-style path to EDLaunch.exe inside the prefix. Passed as an argv arg
# so min-ed-launcher uses its parent as the game dir and skips detection.
ED_LAUNCH_WIN='C:\Program Files (x86)\Steam\steamapps\common\Elite Dangerous\EDLaunch.exe'

CRED_FILE="$ED_PREFIX/drive_c/users/crossover/AppData/Local/min-ed-launcher/.frontier-${PROFILE}.cred"
if [[ ! -f "$CRED_FILE" ]]; then
  warn "no credentials for profile '$PROFILE' at: $CRED_FILE"
  warn "run: scripts/04b-setup-frontier-creds.sh  (or type blind at the prompt)"
fi

info "WINEPREFIX=$WINEPREFIX"
info "wine: $WINE_BIN"
info "launcher: $LAUNCHER_EXE"
info "profile: $PROFILE"
info "MTL_HUD_ENABLED=$MTL_HUD_ENABLED  WINEDEBUG=$WINEDEBUG"

# Reminder, not a fix: ED leaks VRAM under Wine; restart every ~2 hours.
warn "VRAM leak reminder: plan to quit + relaunch every ~2 hours."

# cd into the launcher dir - harmless safety measure in case a future release
# starts reading assets relative to CWD.
cd "$MIN_ED_LAUNCHER_DIR"

cmd=(
  "$WINE_BIN" "$LAUNCHER_EXE" "$ED_LAUNCH_WIN"
  /frontier "$PROFILE"
  /autorun /autoquit
)
if (( USE_CAFFEINATE )) && command -v caffeinate >/dev/null 2>&1; then
  cmd=( caffeinate -dimsu "${cmd[@]}" )
fi

if (( DRY_RUN )); then
  info "DRY: ${cmd[*]}"
  exit 0
fi

exec "${cmd[@]}"
