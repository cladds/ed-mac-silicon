#!/usr/bin/env bash
# nuke-and-pave.sh - destroy prefixes (and optionally deps) for a fresh start.
# Default: removes prefixes + sentinels + cache. Keeps brew installs.
# --all  : also removes the gcenx cask, winetricks, and edmarketconnector.
# --yes  : skip confirmation prompt (for scripted resets).
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

NUKE_ALL=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --all)     NUKE_ALL=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --dry-run) ;; # handled in _common.sh
    *)         warn "unknown flag: $arg" ;;
  esac
done

cat <<EOF
${C_WARN}About to remove:${C_RESET}
  - $ED_PREFIX
  - $TOOLS_PREFIX
  - $SETUP_ROOT (sentinels, logs, cache)
EOF
if (( NUKE_ALL )); then
  cat <<EOF
${C_WARN}--all also removes:${C_RESET}
  - brew cask: gcenx/wine/game-porting-toolkit
  - brew cask: edmarketconnector (if installed)
  - brew formula: winetricks, jq
  - brew tap: gcenx/wine
EOF
fi
echo

if (( ! ASSUME_YES )); then
  read -r -p "Type 'nuke' to confirm: " confirm
  if [[ "$confirm" != "nuke" ]]; then
    info "aborted"
    exit 0
  fi
fi

# Stop any running Wine processes before deleting their prefix.
if command -v wineserver >/dev/null 2>&1; then
  for prefix in "$ED_PREFIX" "$TOOLS_PREFIX"; do
    if [[ -d "$prefix" ]]; then
      info "stopping wineserver in $prefix..."
      WINEPREFIX="$prefix" run wineserver -k || true
    fi
  done
fi

for path in "$ED_PREFIX" "$TOOLS_PREFIX" "$SETUP_ROOT"; do
  if [[ -d "$path" ]]; then
    info "removing $path"
    run rm -rf -- "$path"
  fi
done

if (( NUKE_ALL )); then
  if command -v brew >/dev/null 2>&1; then
    run brew uninstall --cask --force gcenx/wine/game-porting-toolkit || true
    run brew uninstall --cask --force edmarketconnector || true
    run brew uninstall --force winetricks || true
    run brew uninstall --force jq || true
    run brew untap gcenx/wine || true
  fi
fi

ok "nuke complete. start over with: scripts/00-preflight.sh"
