#!/bin/bash

APP_NAME="DreamClipper"
APP_DIR="$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Clean up
rm -rf "$APP_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile
echo "Compiling..."
swiftc -target $(uname -m)-apple-macosx14.0 DreamClipperApp.swift ContentView.swift AppViewModel.swift WindowManager.swift ScreenRecorder.swift GifConverter.swift Theme.swift PlayerView.swift RecordingOverlay.swift RangeSlider.swift DebugLogger.swift -o "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
echo "Copying Info.plist..."
cp Info.plist "$APP_DIR/Contents/Info.plist"

# Copy Resources
if [ -f "AppIcon.icns" ]; then
    echo "Copying AppIcon.icns..."
    cp "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Sign (ad-hoc) to run locally
echo "Signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done! App created at $APP_DIR"
