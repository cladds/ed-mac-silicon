#!/usr/bin/env bash
# 04b-setup-frontier-creds.sh - seed a Frontier credentials profile for
# min-ed-launcher without using its interactive login.
#
# Why the helper approach:
#   - Under Wine, min-ed-launcher's Console.ReadLine/ReadKey does not reliably
#     terminate on Enter (kernel CR/LF handling + Wine console quirks).
#   - The .cred file on Windows contains a DPAPI-encrypted password, which
#     requires running on the same Wine prefix's DPAPI keyring - can't be
#     precomputed from native macOS.
#   - Solution: a tiny .NET helper (tools/mel-cred-helper) reflects the salt
#     out of ClientSupport.dll (same as min-ed-launcher does), runs
#     ProtectedData.Protect under Wine, and writes the two-line .cred file
#     directly. No interactive IO required.
#
# Flags:
#   --profile NAME   profile name to seed (default: "default")
#   --force          overwrite existing cred file
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

PROFILE="default"
FORCE=0
while (( $# )); do
  case "$1" in
    --profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    --dry-run) shift ;;
    *)         warn "unknown flag: $1"; shift ;;
  esac
done

# Kernel/terminal state can get mangled by a killed Wine process (ICRNL off,
# echo raw). Restore sane state before prompting, put back on exit.
if [[ -t 0 ]]; then
  _saved_stty="$(stty -g 2>/dev/null || true)"
  stty sane 2>/dev/null || true
  trap '[[ -n "${_saved_stty:-}" ]] && stty "$_saved_stty" 2>/dev/null || true' EXIT
fi

WINE_BIN="$(require_wine)"
HELPER_EXE="$REPO_ROOT/tools/mel-cred-helper/bin/publish/MelCredHelper.exe"
CLIENT_SUPPORT_DLL="$ED_GAME_DIR/ClientSupport.dll"

if [[ ! -f "$CLIENT_SUPPORT_DLL" ]]; then
  err "ClientSupport.dll missing at: $CLIENT_SUPPORT_DLL"
  err "run the ED install scripts first"
  exit 1
fi

if [[ ! -f "$HELPER_EXE" ]]; then
  warn "credential helper not built yet"
  info "building now - requires dotnet SDK (brew install --cask dotnet-sdk)"
  run "$SCRIPT_DIR/build-cred-helper.sh"
fi

CRED_DIR="$ED_PREFIX/drive_c/users/crossover/AppData/Local/min-ed-launcher"
CRED_FILE="$CRED_DIR/.frontier-${PROFILE}.cred"

if [[ -f "$CRED_FILE" && $FORCE -eq 0 ]]; then
  ok "credentials already exist for profile '$PROFILE': $CRED_FILE"
  ok "pass --force to overwrite"
  exit 0
fi

mkdir -p "$CRED_DIR"
[[ -f "$CRED_FILE" ]] && rm -f "$CRED_FILE"

cat <<EOF
${C_INFO}---------------------------------------------------------------${C_RESET}
Seeding Frontier credentials for profile: ${PROFILE}

A Wine-side helper (MelCredHelper.exe) will DPAPI-encrypt your password
using the exact same salt min-ed-launcher uses and write:
  ${CRED_FILE}

The password is passed as argv to the helper (visible to anyone with ps
access on your machine during the ~1s the helper runs) and never hits
disk in plaintext.
${C_INFO}---------------------------------------------------------------${C_RESET}
EOF

read -r -p "Frontier email: " FDEV_USER
if [[ -z "$FDEV_USER" ]]; then
  err "no email provided"
  exit 1
fi
read -r -s -p "Frontier password: " FDEV_PASS; printf '\n'
if [[ -z "$FDEV_PASS" ]]; then
  err "no password provided"
  exit 1
fi

# Translate the Unix cred path into a Windows path Wine can see. The
# AppData dir lives inside drive_c, so prefix replace is straightforward.
WIN_CRED_FILE="C:${CRED_FILE#$ED_PREFIX/drive_c}"
WIN_CRED_FILE="${WIN_CRED_FILE//\//\\}"
WIN_CLIENT_SUPPORT_DLL='C:\Program Files (x86)\Steam\steamapps\common\Elite Dangerous\ClientSupport.dll'

export WINEPREFIX="$ED_PREFIX" WINEARCH WINEDEBUG=-all WINE="$WINE_BIN"

if (( DRY_RUN )); then
  info "DRY: would run $HELPER_EXE with username + (redacted) password"
  exit 0
fi

info "running MelCredHelper under wine..."
# Direct wine invocation, not under expect - the helper writes the cred
# file and exits in well under a second. No interactive IO involved.
if ! "$WINE_BIN" "$HELPER_EXE" \
      "$WIN_CLIENT_SUPPORT_DLL" \
      "$WIN_CRED_FILE" \
      "$FDEV_USER" \
      "$FDEV_PASS"; then
  unset FDEV_PASS
  err "MelCredHelper.exe failed - see output above"
  exit 1
fi
unset FDEV_PASS

if [[ ! -f "$CRED_FILE" ]]; then
  err "helper reported success but cred file is missing: $CRED_FILE"
  exit 1
fi

# Tidy any leftover wine processes so the next launch starts clean.
pkill -9 -f MelCredHelper.exe 2>/dev/null || true
pkill -9 wineserver 2>/dev/null || true

ok "credentials saved: $CRED_FILE"
ok "next: scripts/launch-ed.sh  (or double-click 'Elite Dangerous.command')"
