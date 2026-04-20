#!/usr/bin/env bash
# import-ca-roots.sh - import macOS's bundled root CAs into the Wine prefix's
# Windows-style trust store so schannel (and anything built on it, including
# self-contained .NET apps) can verify HTTPS certificates.
#
# Why this is needed:
#   A self-contained .NET 8 app running under Wine identifies as Windows, so
#   it uses schannel for TLS. Wine's schannel bridges to GnuTLS, but reads
#   trusted roots from the Windows registry (HKLM\...\SystemCertificates\ROOT
#   \Certificates). A fresh Wine prefix has none imported, so every HTTPS
#   handshake fails with 0x80131506 "The remote certificate is invalid".
#
#   Setting SSL_CERT_FILE / CURL_CA_BUNDLE is unreliable: some Wine builds
#   don't plumb those into schannel. Registry import is definitive.
#
# What this does:
#   1. Parses /etc/ssl/cert.pem (Apple's bundled root CA list, ~128 certs).
#   2. For each cert: DER-encodes it, computes the SHA-1 thumbprint, wraps it
#      in the Windows "Blob" registry format schannel expects.
#   3. Emits a single .reg file and imports it via `wine reg import`.
#
# Idempotent: re-running just overwrites the same registry entries.
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

require_cmd python3 "comes with macOS"
require_cmd openssl "comes with macOS"

WINE_BIN="$(require_wine)"
CA_BUNDLE="${CA_BUNDLE:-/etc/ssl/cert.pem}"

if [[ ! -f "$CA_BUNDLE" ]]; then
  err "CA bundle not found at: $CA_BUNDLE"
  err "override with CA_BUNDLE=/path/to/bundle.pem"
  exit 1
fi

if [[ ! -d "$ED_PREFIX" ]]; then
  err "Wine prefix missing at: $ED_PREFIX"
  exit 1
fi

REG_OUT="$(mktemp -t ed-mac-ca-roots.XXXXXX).reg"
trap 'rm -f "$REG_OUT"' EXIT

info "parsing $CA_BUNDLE and building .reg (may take ~10s for 128 certs)..."
python3 - "$CA_BUNDLE" > "$REG_OUT" <<'PY'
import hashlib, subprocess, sys
from pathlib import Path

# Windows cert-store "Blob" is a sequence of property records. The minimum
# required set for a trusted root is CERT_SHA1_HASH_PROP_ID (0x03) and the
# raw DER-encoded cert (0x20). Each record is:
#   DWORD property_id
#   DWORD flags  (always 1)
#   DWORD length
#   BYTE  data[length]

SHA1_HASH_PROP_ID = 0x03
CERT_PROP_ID       = 0x20

def parse_pem_bundle(path):
    certs, cur, inside = [], [], False
    for line in Path(path).read_text().splitlines():
        if line.startswith("-----BEGIN CERTIFICATE-----"):
            inside = True
            cur = [line]
        elif line.startswith("-----END CERTIFICATE-----") and inside:
            cur.append(line)
            certs.append("\n".join(cur) + "\n")
            cur, inside = [], False
        elif inside:
            cur.append(line)
    return certs

def pem_to_der(pem: str) -> bytes:
    r = subprocess.run(
        ["openssl", "x509", "-outform", "DER"],
        input=pem.encode(), capture_output=True,
    )
    if r.returncode != 0:
        return b""
    return r.stdout

def build_blob(der: bytes) -> tuple[bytes, str]:
    sha1 = hashlib.sha1(der).digest()
    out = bytearray()
    for prop_id, data in ((SHA1_HASH_PROP_ID, sha1), (CERT_PROP_ID, der)):
        out += prop_id.to_bytes(4, "little")
        out += (1).to_bytes(4, "little")
        out += len(data).to_bytes(4, "little")
        out += data
    return bytes(out), sha1.hex().upper()

def format_hex_binary(blob: bytes) -> str:
    """Format bytes as .reg-compatible hex: with line continuations at ~80 cols."""
    parts = [f"{b:02x}" for b in blob]
    lines = []
    chunk = []
    for part in parts:
        chunk.append(part)
        # 25 bytes per line keeps us under 80 cols including the prefix/indent
        if len(chunk) == 25:
            lines.append(",".join(chunk))
            chunk = []
    if chunk:
        lines.append(",".join(chunk))
    return ",\\\n  ".join(lines)

def main():
    bundle = sys.argv[1]
    out = sys.stdout
    out.write("Windows Registry Editor Version 5.00\r\n\r\n")
    n = 0
    for pem in parse_pem_bundle(bundle):
        der = pem_to_der(pem)
        if not der:
            continue
        blob, tp = build_blob(der)
        hex_body = format_hex_binary(blob)
        out.write(
            f"[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\SystemCertificates\\Root\\Certificates\\{tp}]\r\n"
            f'"Blob"=hex:{hex_body}\r\n\r\n'
        )
        n += 1
    print(f"# wrote {n} cert entries", file=sys.stderr)

main()
PY

CERT_COUNT=$(grep -c "^\[HKEY_LOCAL_MACHINE" "$REG_OUT" || true)
info "generated .reg with $CERT_COUNT root certs ($(wc -c < "$REG_OUT") bytes)"

export WINEPREFIX="$ED_PREFIX" WINEARCH WINEDEBUG=-all WINE="$WINE_BIN"
info "importing into Wine registry..."
run "$WINE_BIN" reg import "$REG_OUT"

# Let wineserver flush the registry write to disk before the next launch.
pkill -f wineserver 2>/dev/null || true
sleep 1

ok "imported $CERT_COUNT root CAs into $ED_PREFIX"
ok "retry: ./scripts/launch-ed.sh  (or double-click Elite Dangerous.command)"
