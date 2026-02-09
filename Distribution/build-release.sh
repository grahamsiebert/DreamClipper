#!/bin/bash

# DreamClipper Release Build Script
# Usage: ./build-release.sh [version]
# Example: ./build-release.sh 1.0.0

set -e

VERSION="${1:-1.0.0}"
APP_NAME="DreamClipper"
BUNDLE_ID="com.dreamclipper.gifcreator"
DEVELOPER_ID="Developer ID Application: YOUR NAME (TEAM_ID)"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "========================================="
echo "Building $APP_NAME v$VERSION"
echo "========================================="

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Archive the app
echo ""
echo "Step 1: Creating archive..."
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive

# Step 2: Export the archive (signed with Developer ID)
echo ""
echo "Step 2: Exporting signed app..."

# Create export options plist
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>922D33U8V6</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"

# Step 3: Notarize the app
echo ""
echo "Step 3: Notarizing app..."
echo "(This may take a few minutes)"

# Create a zip for notarization
ZIP_PATH="$BUILD_DIR/$APP_NAME-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Submit for notarization
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "AC_PASSWORD" \
    --wait

# Staple the notarization ticket
echo ""
echo "Step 4: Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# Step 5: Create DMG
echo ""
echo "Step 5: Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary folder for DMG contents
DMG_TEMP="$BUILD_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp folder
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symlink to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Notarize the DMG
echo ""
echo "Step 6: Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "AC_PASSWORD" \
    --wait

xcrun stapler staple "$DMG_PATH"

# Step 7: Generate Sparkle signature
echo ""
echo "Step 7: Generating Sparkle signature..."
echo "Run this command to sign for Sparkle:"
echo ""
echo "  ./bin/sign_update \"$DMG_PATH\""
echo ""

# Get file size
FILE_SIZE=$(stat -f%z "$DMG_PATH")
echo "DMG Size: $FILE_SIZE bytes"

echo ""
echo "========================================="
echo "Build complete!"
echo "DMG: $DMG_PATH"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Sign the DMG with Sparkle: ./bin/sign_update \"$DMG_PATH\""
echo "2. Upload DMG to your server"
echo "3. Update appcast.xml with signature and file size"
echo "4. Upload appcast.xml to your server"
