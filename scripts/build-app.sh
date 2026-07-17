#!/bin/bash

# MacUtilities — build, sign, and install the unified background app.
# Single binary, single permission (Accessibility). No sudo required.

set -e

APP_NAME="MacUtilities"
BUNDLE_ID="com.mathatinlabs.macutilities"
VERSION="1.0"

# Locate the source directory (repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT_DIR/src/mac-utilities.swift"
ICON="$ROOT_DIR/assets/AppIcon.icns"

BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YEL='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
warn()  { echo -e "${YEL}⚠ $1${NC}"; }

# --- Uninstall ---
if [[ "$1" == "uninstall" || "$1" == "--uninstall" ]]; then
    info "Uninstalling MacUtilities..."
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"          && ok "Removed launch agent"
    rm -rf "$INSTALLED_APP" && ok "Removed $INSTALLED_APP"
    echo
    info "Also remove 'MacUtilities' from:"
    echo "  System Settings → Privacy & Security → Accessibility"
    exit 0
fi

command -v swiftc >/dev/null || { echo "swiftc not found: xcode-select --install"; exit 1; }

# --- 1. Bundle skeleton ---
info "Creating bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# --- 2. Compile ---
info "Compiling..."
swiftc -O -o "$MACOS_DIR/$APP_NAME" "$SRC" \
    -framework Cocoa -framework SwiftUI -framework Foundation
ok "Compiled"

# --- 3. Icon ---
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$RES_DIR/AppIcon.icns"
    ok "Icon added"
else
    warn "Icon not found ($ICON) — continuing without it"
fi

# --- 4. Info.plist ---
cat > "$APP_DIR/Contents/Info.plist" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Mac Utilities</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOL
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"
ok "Info.plist written"

# --- 5. Ad-hoc signature ---
# (For distribution later: codesign --sign "Developer ID Application: ...")
info "Signing (ad-hoc)..."
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR" 2>/dev/null \
    && ok "Signed" || warn "Signing skipped"

# --- 6. Install (~/Applications) ---
info "Installing: $INSTALLED_APP"
mkdir -p "$INSTALL_DIR"
# Stop it if it is already running
[[ -f "$PLIST" ]] && launchctl unload "$PLIST" 2>/dev/null || true
rm -rf "$INSTALLED_APP"
cp -R "$APP_DIR" "$INSTALLED_APP"
ok "Installed"

# --- 7. LaunchAgent (single service) ---
cat > "$PLIST" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array><string>$INSTALLED_APP/Contents/MacOS/$APP_NAME</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOL
ok "LaunchAgent created"

# --- 8. Start ---
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST" 2>/dev/null || true
ok "Service started"

echo
ok "Done!"
echo
info "Final step — grant ONE permission:"
echo "  System Settings → Privacy & Security → Accessibility → enable MacUtilities"
echo
info "It activates automatically the moment you grant access (no need to relaunch the app)."
