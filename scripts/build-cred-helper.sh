#!/usr/bin/env bash
# build-cred-helper.sh - compile tools/mel-cred-helper to a self-contained
# Windows x64 single-file executable that runs under Wine.
#
# Requires dotnet SDK on macOS: `brew install --cask dotnet-sdk`
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

init_logging
install_err_trap

require_cmd dotnet "brew install --cask dotnet-sdk"

HELPER_DIR="$REPO_ROOT/tools/mel-cred-helper"
if [[ ! -d "$HELPER_DIR" ]]; then
  err "helper source missing at $HELPER_DIR"
  exit 1
fi

info "publishing MelCredHelper (win-x64, self-contained, single-file)..."
run dotnet publish "$HELPER_DIR/MelCredHelper.csproj" \
  -c Release \
  -r win-x64 \
  --self-contained true \
  -p:PublishSingleFile=true \
  -o "$HELPER_DIR/bin/publish"

OUT_EXE="$HELPER_DIR/bin/publish/MelCredHelper.exe"
if [[ ! -f "$OUT_EXE" ]]; then
  err "publish completed but $OUT_EXE not found"
  exit 1
fi

ok "built: $OUT_EXE"
ok "run scripts/04b-setup-frontier-creds.sh to use it"
