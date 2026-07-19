#!/bin/bash

# PC Mouse for Mac — build a distributable, notarized DMG.
#
# This is a SKELETON: it requires a paid Apple Developer account and a
# "Developer ID Application" certificate installed in your keychain. Local
# self-signed builds (scripts/build-app.sh) do NOT need any of this.
#
# ── One-time setup ──────────────────────────────────────────────────────────
#   1. Join the Apple Developer Program ($99/yr).
#   2. In Xcode or the developer portal, create a "Developer ID Application"
#      certificate and install it in your login keychain.
#   3. Create an app-specific password at https://appleid.apple.com → Sign-In
#      & Security → App-Specific Passwords.
#   4. Store notarization credentials once as a reusable profile:
#        xcrun notarytool store-credentials "PCMouseForMac-Notary" \
#            --apple-id "you@example.com" \
#            --team-id  "YOURTEAMID" \
#            --password "xxxx-xxxx-xxxx-xxxx"
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="PCMouseForMac-Notary" \
#   bash scripts/release.sh
#
# Result: dist/PCMouseForMac-<version>.dmg (signed, notarized, stapled).

set -e

APP_NAME="PCMouseForMac"
VERSION="1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_APP="$ROOT_DIR/build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-stage"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
VOL_NAME="$APP_NAME"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
die()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

# --- Preconditions ---
[[ -n "$DEVELOPER_ID" ]]   || die "Set DEVELOPER_ID to your 'Developer ID Application: …' name"
[[ -n "$NOTARY_PROFILE" ]] || die "Set NOTARY_PROFILE (see 'notarytool store-credentials' above)"
command -v xcrun >/dev/null || die "xcrun not found (install Xcode)"

# --- 1. Build a Developer ID–signed .app (hardened runtime, no install) ---
info "Building signed app bundle..."
MU_SIGN_IDENTITY="$DEVELOPER_ID" MU_NO_INSTALL=1 bash "$SCRIPT_DIR/build-app.sh"
[[ -d "$BUILD_APP" ]] || die "Build did not produce $BUILD_APP"

# --- 2. Stage a drag-to-install DMG layout ---
info "Staging DMG contents..."
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$BUILD_APP" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"   # drag target

# --- 3. Build the DMG ---
info "Creating DMG..."
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE_DIR" \
    -ov -format UDZO "$DMG_PATH" >/dev/null
ok "DMG created: $DMG_PATH"

# --- 4. Sign the DMG ---
info "Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

# --- 5. Notarize (submit + wait) ---
info "Submitting for notarization (this can take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
    || die "Notarization failed — check 'xcrun notarytool log'"

# --- 6. Staple the ticket so it validates offline ---
info "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH" && ok "Stapled and validated"

# --- 7. Cleanup ---
rm -rf "$STAGE_DIR"
echo
ok "Release ready: $DMG_PATH"
info "Users can now download it, drag PC Mouse for Mac to Applications, and open it"
info "with no Gatekeeper warning."
