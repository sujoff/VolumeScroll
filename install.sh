#!/bin/bash
set -e

REPO="sujoff/VolumeScroll"
RAW="https://raw.githubusercontent.com/$REPO/main"
APP_NAME="VolumeScroll.app"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME"
TMP_DIR=$(mktemp -d)

echo ""
echo "  VolumeScroller Installer"
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

echo "  ⬇️  Downloading source..."
curl -sL "$RAW/AppDelegate.swift" -o "$TMP_DIR/AppDelegate.swift"
curl -sL "$RAW/main.swift"        -o "$TMP_DIR/main.swift"
curl -sL "$RAW/Info.plist"        -o "$TMP_DIR/Info.plist"

echo "  🔨 Building..."
cd "$TMP_DIR"
mkdir -p "$APP_NAME/Contents/MacOS" "$APP_NAME/Contents/Resources"

swiftc AppDelegate.swift main.swift \
    -framework Cocoa \
    -framework CoreAudio \
    -framework ServiceManagement \
    -o "$APP_NAME/Contents/MacOS/VolumeScroll" \
    -target arm64-apple-macos13.0

cp Info.plist "$APP_NAME/Contents/Info.plist"

echo "  📦 Installing to /Applications..."
rm -rf "$APP_PATH"
cp -r "$APP_NAME" "$INSTALL_DIR/"

echo "  ✅ Done! Launching VolumeScroll..."
echo ""
echo "  👉 First launch: macOS will ask for Accessibility permission."
echo "     Go to System Settings → Privacy & Security → Accessibility"
echo "     and enable VolumeScroll."
echo ""

open "$APP_PATH"
rm -rf "$TMP_DIR"
