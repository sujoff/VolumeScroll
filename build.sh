#!/bin/bash
set -e

APP="VolumeScroll.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

swiftc AppDelegate.swift main.swift \
    -framework Cocoa \
    -framework CoreAudio \
    -framework ServiceManagement \
    -o "$MACOS/VolumeScroll" \
    -target arm64-apple-macos13.0

cp Info.plist "$CONTENTS/Info.plist"

echo "✅ Built: VolumeScroll.app"
echo "Run: open VolumeScroll.app"
ech  "Feel free to raise issue in github if any trouble!! "