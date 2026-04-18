#!/usr/bin/env bash
# 01-install-deps.sh - Homebrew, Rosetta 2, gcenx tap, GPTK Wine, winetricks.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

KEY="01-install-deps"
if skip_if_done "$KEY"; then
  exit 0
fi

require_arm64

# ----- Homebrew -----
if ! command -v brew >/dev/null 2>&1; then
  info "installing Homebrew (non-interactive)..."
  run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available for the rest of this shell.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
ok "brew: $(command -v brew)"

# ----- Rosetta 2 -----
# GPTK's Wine still loads x86_64 Windows code, and some brew bottles in the
# gcenx tap have historically been x86_64. Install Rosetta if missing.
if ! /usr/bin/pgrep -q oahd; then
  info "installing Rosetta 2 (required for x86_64 translation)..."
  run softwareupdate --install-rosetta --agree-to-license
else
  ok "Rosetta 2 already present"
fi

# ----- gcenx tap -----
if ! brew tap | grep -qx 'gcenx/wine'; then
  info "tapping gcenx/wine..."
  run brew tap gcenx/wine
else
  ok "gcenx/wine tap already present"
fi

# ----- GPTK Wine -----
# The cask is large; only install if the wine binary cannot be located.
if ! find_wine >/dev/null; then
  info "installing GPTK-bundled Wine (gcenx/wine/game-porting-toolkit)..."
  info "this is a multi-GB download; grab a coffee."
  # Homebrew removed --no-quarantine in 2025, so install normally and strip
  # the com.apple.quarantine attribute ourselves afterward. Without this, Wine
  # inside the cask fails to load its own components under Gatekeeper.
  run brew install --cask gcenx/wine/game-porting-toolkit
  info "removing Gatekeeper quarantine from GPTK components..."
  # Candidates: the cask's app bundle and the brew opt prefix.
  gptk_paths=()
  if [[ -d "/Applications/Game Porting Toolkit.app" ]]; then
    gptk_paths+=("/Applications/Game Porting Toolkit.app")
  fi
  # brew --prefix exits non-zero for casks; swallow that without tripping ERR.
  gptk_prefix="$(brew --prefix game-porting-toolkit 2>/dev/null || true)"
  if [[ -n "$gptk_prefix" && -d "$gptk_prefix" ]]; then
    gptk_paths+=("$gptk_prefix")
  fi
  for p in "${gptk_paths[@]}"; do
    run xattr -dr com.apple.quarantine "$p" 2>/dev/null || true
  done
else
  ok "GPTK Wine already installed at: $(find_wine)"
fi

# ----- winetricks -----
if ! command -v winetricks >/dev/null 2>&1; then
  info "installing winetricks..."
  run brew install winetricks
else
  ok "winetricks: $(command -v winetricks)"
fi

# ----- jq (for parsing GitHub release JSON in 04-install-launcher.sh) -----
if ! command -v jq >/dev/null 2>&1; then
  info "installing jq (used to parse min-ed-launcher release metadata)..."
  run brew install jq
fi

# ----- Final verification -----
if ! WINE_BIN="$(find_wine)"; then
  err "Wine binary still not found after install. Inspect the gcenx cask manually."
  exit 1
fi
ok "wine: $WINE_BIN"
"$WINE_BIN" --version || warn "wine refused to report a version; investigate before proceeding"

run mark_done "$KEY"
ok "dependencies installed"
