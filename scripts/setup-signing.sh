#!/bin/bash

# Creates a stable, self-signed code-signing identity for MacUtilities.
#
# Why: ad-hoc signing gives the app a new code identity on every rebuild, which
# makes macOS invalidate the Accessibility (TCC) permission each time. A stable
# self-signed certificate keeps the identity constant, so you grant the
# permission ONCE and it survives every rebuild.
#
# The certificate is generated locally, per machine (the private key never
# leaves your Keychain and is never committed). Idempotent: re-running is a
# no-op once the identity exists. Fully non-interactive.

set -e

IDENTITY="MacUtilities Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/macutil-signing.keychain-db"
KC_PASS="macutil"          # password for the dedicated signing keychain
P12_PASS="macutil-p12"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }

# Already set up? (identity visible in the current search list)
if security find-identity 2>/dev/null | grep -q "$IDENTITY"; then
    ok "Signing identity already present: $IDENTITY"
    exit 0
fi

info "Creating self-signed code-signing certificate..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -nodes \
    -subj "/CN=$IDENTITY" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1
openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$P12_PASS" -name "$IDENTITY" >/dev/null 2>&1

info "Importing into a dedicated keychain..."
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock timeout
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -A >/dev/null 2>&1
# Let codesign use the key without an interactive prompt
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1

# Append our keychain to the EXISTING search list (never clobber the user's
# other keychains). Read current entries, add ours only if missing.
CURRENT=()
while IFS= read -r line; do
    kc="$(echo "$line" | tr -d '"' | xargs)"
    [[ -n "$kc" ]] && CURRENT+=("$kc")
done < <(security list-keychains -d user)
if ! printf '%s\n' "${CURRENT[@]}" | grep -q "macutil-signing"; then
    security list-keychains -d user -s "${CURRENT[@]}" "$KEYCHAIN" >/dev/null 2>&1
fi

if security find-identity "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    ok "Signing identity ready: $IDENTITY"
else
    echo "Failed to create signing identity" >&2
    exit 1
fi
