#!/usr/bin/env bash
# 00-preflight.sh - verify hardware, OS, Xcode CLT + Xcode.app, and disk space.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

KEY="00-preflight"
if skip_if_done "$KEY"; then
  exit 0
fi

info "checking Apple Silicon..."
require_arm64
ok "arch: $(uname -m)"

info "checking macOS version..."
require_macos_min 14
ok "macOS: $(sw_vers -productVersion)"

info "checking Xcode Command Line Tools..."
if ! xcode-select -p >/dev/null 2>&1; then
  err "Xcode Command Line Tools missing. Install with:"
  err "  xcode-select --install"
  exit 1
fi
ok "Xcode CLT at: $(xcode-select -p)"

info "checking full Xcode.app (needed by GPTK's Metal toolchain)..."
XCODE_APP=""
for c in /Applications/Xcode.app /Applications/Xcode-beta.app; do
  if [[ -d "$c" ]]; then XCODE_APP="$c"; break; fi
done
if [[ -z "$XCODE_APP" ]]; then
  err "Xcode.app not found in /Applications."
  err "Install it from the Mac App Store (about 15GB), then re-run this script."
  err "After install, also accept the license:  sudo xcodebuild -license accept"
  exit 1
fi
ok "Xcode.app: $XCODE_APP"

# Confirm xcode-select points at Xcode.app, not just the CLT shim.
if [[ "$(xcode-select -p)" != "$XCODE_APP/Contents/Developer" ]]; then
  warn "xcode-select points at the CLT shim, not Xcode.app."
  warn "GPTK needs the full Xcode toolchain. Switch with:"
  warn "  sudo xcode-select -s '$XCODE_APP/Contents/Developer'"
fi

info "checking free disk space (need ~150GB for ED + tools + prefix overhead)..."
# df on macOS gives 512-byte blocks by default; -g gives gigabytes.
free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
if [[ -z "$free_gb" ]]; then
  warn "could not parse free space; continuing"
else
  if (( free_gb < 150 )); then
    err "only ${free_gb}GB free in $HOME; need at least 150GB"
    exit 1
  fi
  ok "free space: ${free_gb}GB"
fi

run mark_done "$KEY"
ok "preflight complete"
