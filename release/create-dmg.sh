#!/bin/bash
set -e

# DreamClipper DMG Creation Script
# Usage: ./create-dmg.sh /path/to/DreamClipper.app

APP_PATH="$1"
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString)
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion)
DMG_NAME="DreamClipper-${VERSION}.dmg"
VOLUME_NAME="DreamClipper"

if [ -z "$APP_PATH" ]; then
    echo "Usage: ./create-dmg.sh /path/to/DreamClipper.app"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

echo "Creating DMG for DreamClipper v${VERSION} (${BUILD})..."

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Working in $TEMP_DIR"

# Copy app to temp directory
cp -R "$APP_PATH" "$TEMP_DIR/"

# Create symlink to Applications folder
ln -s /Applications "$TEMP_DIR/Applications"

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$TEMP_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "Created: $DMG_NAME"
echo ""
echo "Next steps:"
echo "1. Notarize the DMG:"
echo "   xcrun notarytool submit $DMG_NAME --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password YOUR_APP_SPECIFIC_PASSWORD --wait"
echo ""
echo "2. Staple the notarization ticket:"
echo "   xcrun stapler staple $DMG_NAME"
echo ""
echo "3. Sign for Sparkle (run from Sparkle bin directory):"
echo "   ./sign_update $DMG_NAME"
echo ""
echo "4. Update appcast.xml with the signature and upload both files"
