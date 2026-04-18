#!/usr/bin/env bash
# 04-install-launcher.sh - drop min-ed-launcher into the ED prefix.
# The Frontier launcher fails under Wine; min-ed-launcher is the workaround.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

KEY="04-install-launcher"
if skip_if_done "$KEY"; then
  exit 0
fi

set -a
# shellcheck source=../config/ed-launch.env
source "$REPO_ROOT/config/ed-launch.env"
set +a

require_cmd jq "brew install jq"
require_cmd curl "comes with macOS"
require_cmd unzip "comes with macOS"

if [[ ! -d "$ED_PREFIX" ]]; then
  err "ED prefix missing at: $ED_PREFIX. Run 02-create-ed-prefix.sh first."
  exit 1
fi

# Resolve the latest release asset (Windows x64 zip).
API_URL="https://api.github.com/repos/rfvgyhn/min-ed-launcher/releases/latest"
info "querying GitHub for the latest min-ed-launcher release..."

RELEASE_JSON="$(curl -fsSL "$API_URL")"
TAG="$(jq -r '.tag_name' <<<"$RELEASE_JSON")"
ASSET_URL="$(jq -r '.assets[] | select(.name | test("win-x64.*\\.zip$")) | .browser_download_url' <<<"$RELEASE_JSON" | head -n1)"

if [[ -z "$ASSET_URL" || "$ASSET_URL" == "null" ]]; then
  err "could not find a win-x64 .zip asset in release $TAG"
  err "check https://github.com/rfvgyhn/min-ed-launcher/releases manually"
  exit 1
fi

ok "latest release: $TAG"
ok "asset:         $ASSET_URL"

CACHE_DIR="$SETUP_ROOT/cache"
mkdir -p "$CACHE_DIR"
ZIP_PATH="$CACHE_DIR/min-ed-launcher-$TAG-win-x64.zip"

if [[ ! -f "$ZIP_PATH" ]]; then
  info "downloading min-ed-launcher..."
  run curl -fsSL -o "$ZIP_PATH" "$ASSET_URL"
else
  ok "asset already cached: $ZIP_PATH"
fi

# Install into the prefix.
# Recent releases (>=0.12) ship the zip with a single top-level directory
# like `min-ed-launcher_vX.Y.Z_win-x64/`. Older releases extracted flat.
# Extract to a staging dir, then flatten if needed so MinEdLauncher.exe
# always lands directly in $MIN_ED_LAUNCHER_DIR.
info "installing to: $MIN_ED_LAUNCHER_DIR"
run mkdir -p "$MIN_ED_LAUNCHER_DIR"
STAGING="$(mktemp -d -t min-ed-launcher.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
run unzip -oq "$ZIP_PATH" -d "$STAGING"

# If the zip contained exactly one top-level dir (and no loose files), descend
# into it. Otherwise assume a flat layout.
SRC="$STAGING"
shopt -s nullglob dotglob
entries=("$STAGING"/*)
shopt -u nullglob dotglob
if (( ${#entries[@]} == 1 )) && [[ -d "${entries[0]}" ]]; then
  SRC="${entries[0]}"
fi

# Copy contents (not the dir itself) into the install location.
run cp -R "$SRC"/. "$MIN_ED_LAUNCHER_DIR/"

if [[ ! -f "$MIN_ED_LAUNCHER_DIR/MinEdLauncher.exe" ]]; then
  err "MinEdLauncher.exe not found at: $MIN_ED_LAUNCHER_DIR/MinEdLauncher.exe"
  err "zip layout may have changed upstream; inspect $STAGING before it's cleaned up"
  trap - EXIT
  exit 1
fi

# settings.json location gotcha: min-ed-launcher looks for settings.json at
# %LOCALAPPDATA%\min-ed-launcher\settings.json, NOT next to the exe. A file
# dropped next to the exe is silently ignored. The launcher auto-generates a
# default file in AppData on first run; we overwrite it with our template so
# the defaults we want (apiUri, filterOverrides, etc.) stick. `launch-ed.sh`
# doesn't rely on gameLocation — it passes EDLaunch.exe as an argv argument
# which bypasses install-dir discovery entirely.
APPDATA_LAUNCHER_DIR="$ED_PREFIX/drive_c/users/crossover/AppData/Local/min-ed-launcher"
SETTINGS_DST="$APPDATA_LAUNCHER_DIR/settings.json"
SETTINGS_SRC="$REPO_ROOT/config/min-ed-launcher.json"
run mkdir -p "$APPDATA_LAUNCHER_DIR"
if [[ ! -f "$SETTINGS_DST" ]]; then
  info "installing settings.json template to $SETTINGS_DST"
  run cp "$SETTINGS_SRC" "$SETTINGS_DST"
else
  ok "settings.json already present in AppData (leaving your edits intact)"
fi

cat <<EOF
${C_INFO}---------------------------------------------------------------${C_RESET}
min-ed-launcher installed.

Next: seed your Frontier credentials once, then launch.
  1. scripts/04b-setup-frontier-creds.sh   (one-time, writes encrypted .cred)
  2. scripts/launch-ed.sh                  (day-to-day launcher)

If you'd rather not store credentials on disk, skip step 1 and type them
each launch - but note Wine's stdin echo is broken, so typing is blind.
${C_INFO}---------------------------------------------------------------${C_RESET}
EOF

run mark_done "$KEY"
ok "launcher install complete"
ok "next: scripts/04b-setup-frontier-creds.sh"
