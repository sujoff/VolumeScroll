#!/bin/bash
set -e

echo ""
echo "  VolumeScroll Installer"
echo "  ──────────────────────"
echo ""

# Check for Xcode Command Line Tools
if ! command -v swiftc &> /dev/null; then
    echo "  ⚠️  Xcode Command Line Tools not found."
    echo "  Installing... (you may see a system prompt)"
    xcode-select --install
    echo ""
    echo "  Once installed, run this script again."
    exit 1
fi

APP_NAME="VolumeScroll.app"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "  🔨 Building..."

# Build
mkdir -p "$APP_NAME/Contents/MacOS" "$APP_NAME/Contents/Resources"

swiftc "$SCRIPT_DIR/AppDelegate.swift" "$SCRIPT_DIR/main.swift" \
    -framework Cocoa \
    -framework CoreAudio \
    -framework ServiceManagement \
    -o "$APP_NAME/Contents/MacOS/VolumeScroll" \
    -target arm64-apple-macos13.0 2>&1

cp "$SCRIPT_DIR/Info.plist" "$APP_NAME/Contents/Info.plist"

echo "  📦 Installing to /Applications..."

# Remove old version if exists
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
fi

cp -r "$APP_NAME" "$INSTALL_DIR/"
rm -rf "$APP_NAME"

echo "  ✅ Done! Launching VolumeScroll..."
echo ""
echo "  👉 First launch: macOS will ask for Accessibility permission."
echo "     Go to System Settings → Privacy & Security → Accessibility"
echo "     and enable VolumeScroll."
echo ""

open "$APP_PATH"
