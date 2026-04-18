# shellcheck shell=bash
# Shared helpers for ed-mac setup scripts.
# Sourced from each top-level script after `set -euo pipefail` is set.

# Propagate ERR trap into functions and subshells so errors inside run(),
# require_wine(), etc. actually trigger on_err with context.
set -E

# ----- paths -----
SETUP_ROOT="${SETUP_ROOT:-$HOME/Games/.ed-mac-setup}"
SENTINEL_DIR="$SETUP_ROOT/sentinels"
LOG_DIR="$SETUP_ROOT/logs"

# ----- colours -----
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_INFO=$'\033[36m'    # cyan
  C_OK=$'\033[32m'      # green
  C_WARN=$'\033[33m'    # yellow
  C_ERR=$'\033[31m'     # red
  C_DIM=$'\033[2m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''
fi

info()    { printf '%s[info]%s %s\n'  "$C_INFO" "$C_RESET" "$*"; }
ok()      { printf '%s[ok]%s   %s\n'  "$C_OK"   "$C_RESET" "$*"; }
warn()    { printf '%s[warn]%s %s\n'  "$C_WARN" "$C_RESET" "$*" >&2; }
err()     { printf '%s[err]%s  %s\n'  "$C_ERR"  "$C_RESET" "$*" >&2; }
dim()     { printf '%s%s%s\n'         "$C_DIM"  "$*" "$C_RESET"; }

# ----- dry-run -----
DRY_RUN=0
for arg in "${@:-}"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=1
  fi
done

run() {
  if (( DRY_RUN )); then
    info "DRY: $*"
  else
    "$@"
  fi
}

# ----- logging -----
init_logging() {
  local script_name log_file ts
  script_name="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$LOG_DIR"
  log_file="$LOG_DIR/${script_name}-${ts}.log"
  # Tee everything to the log while keeping it on the user's terminal.
  exec > >(tee -a "$log_file") 2>&1
  dim "log: $log_file"
}

# ----- error trap -----
on_err() {
  local exit_code=$?
  err "failed at line $1 (exit $exit_code): $2"
  exit "$exit_code"
}
install_err_trap() {
  trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
}

# ----- sentinels -----
mkdir -p "$SENTINEL_DIR"

mark_done() { touch "$SENTINEL_DIR/$1.done"; }
is_done()   { [[ -f "$SENTINEL_DIR/$1.done" ]]; }

skip_if_done() {
  local key="$1"
  if is_done "$key"; then
    ok "$key already complete (sentinel: $SENTINEL_DIR/$key.done), skipping"
    return 0
  fi
  return 1
}

# ----- preconditions -----
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
    if [[ -n "${2:-}" ]]; then
      err "  install with: $2"
    fi
    exit 1
  fi
}

require_arm64() {
  local arch
  arch="$(uname -m)"
  if [[ "$arch" != "arm64" ]]; then
    err "Apple Silicon required (this machine reports: $arch)"
    exit 1
  fi
}

require_macos_min() {
  local need="$1" have
  have="$(sw_vers -productVersion)"
  # Compare major.minor numerically.
  local need_major have_major
  need_major="${need%%.*}"
  have_major="${have%%.*}"
  if (( have_major < need_major )); then
    err "macOS $need or later required (have $have)"
    exit 1
  fi
}

# Locate the GPTK-bundled wine64 binary. The gcenx cask has shipped it from a
# few places over time, so probe the known locations.
find_wine() {
  local candidates=()
  if command -v brew >/dev/null 2>&1; then
    local prefix
    prefix="$(brew --prefix game-porting-toolkit 2>/dev/null || true)"
    [[ -n "$prefix" ]] && candidates+=("$prefix/bin/wine64")
  fi
  candidates+=(
    "/usr/local/opt/game-porting-toolkit/bin/wine64"
    "/opt/homebrew/opt/game-porting-toolkit/bin/wine64"
    "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -x "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  if command -v wine64 >/dev/null 2>&1; then
    command -v wine64
    return 0
  fi
  return 1
}

require_wine() {
  local w
  if ! w="$(find_wine)"; then
    err "GPTK Wine not found. Run scripts/01-install-deps.sh first."
    exit 1
  fi
  printf '%s\n' "$w"
}

# Refuse to run as root. GPTK + Wine should live under the user's homebrew prefix.
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  err "do not run as root; this installs into your user homebrew prefix"
  exit 1
fi
