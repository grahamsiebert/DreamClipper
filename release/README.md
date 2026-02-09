# DreamClipper Release Guide

## One-Time Setup

### 1. Add Sparkle to Xcode Project

1. Open `DreamClipper.xcodeproj` in Xcode
2. Go to **File > Add Package Dependencies...**
3. Enter: `https://github.com/sparkle-project/Sparkle`
4. Select version **2.x** (latest 2.x.x)
5. Click **Add Package**
6. Make sure "Sparkle" is added to the DreamClipper target

### 2. Generate Sparkle Signing Keys

After adding Sparkle, find the `generate_keys` tool:

```bash
# Find the tool (path varies based on Xcode derived data location)
find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -type f 2>/dev/null | head -1

# Or download Sparkle separately
curl -L -o Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
tar -xf Sparkle.tar.xz
./Sparkle-2.6.4/bin/generate_keys
```

This will:
- Store your **private key** in the macOS Keychain (keep this safe!)
- Output your **public key** - copy this for the next step

### 3. Update Info.plist

Open `Info.plist` and update these values:

- `SUFeedURL`: Change `https://yourdomain.com/appcast.xml` to your actual URL
- `SUPublicEDKey`: Paste the public key from step 2

### 4. Create Developer ID Certificate

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
2. Create a **Developer ID Application** certificate if you don't have one
3. Download and install it in your Keychain

### 5. Configure Xcode Signing

1. Open project in Xcode
2. Select the **DreamClipper** target
3. Go to **Signing & Capabilities**
4. Set **Signing Certificate** to **Developer ID Application**
5. Ensure your Team is selected

---

## Release Process

### Step 1: Bump Version Numbers

In Xcode or `Info.plist`:
- `CFBundleShortVersionString` (e.g., "1.1")
- `CFBundleVersion` (e.g., "2") - increment for each build

### Step 2: Archive the App

1. In Xcode: **Product > Archive**
2. In Organizer: **Distribute App**
3. Select **Developer ID**
4. Select **Upload** (for automatic notarization)
5. Wait for notarization to complete
6. Click **Export Notarized App**
7. Save the `.app` bundle

### Step 3: Create DMG

```bash
cd /Users/a.graham/DreamClipper/release
chmod +x create-dmg.sh
./create-dmg.sh /path/to/exported/DreamClipper.app
```

### Step 4: Notarize the DMG

```bash
# Submit for notarization
xcrun notarytool submit DreamClipper-1.1.dmg \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD \
  --wait

# Staple the ticket
xcrun stapler staple DreamClipper-1.1.dmg
```

**Tip**: Create an app-specific password at https://appleid.apple.com/account/manage

### Step 5: Sign for Sparkle

```bash
# Find sign_update tool
./Sparkle-2.6.4/bin/sign_update DreamClipper-1.1.dmg

# Output will be like:
# sparkle:edSignature="xxxxx" length="12345678"
```

### Step 6: Update Appcast

Edit `appcast.xml`:

1. Add a new `<item>` block at the top (inside `<channel>`)
2. Update version numbers, description, and release notes
3. Paste the `sparkle:edSignature` from step 5
4. Update the `length` attribute
5. Set the correct download URL

### Step 7: Upload Files

Upload to your web server:
1. `DreamClipper-1.1.dmg` to your releases folder
2. Updated `appcast.xml` to the URL in your `SUFeedURL`

---

## Testing Updates

1. Install an older version of the app
2. Launch it - Sparkle should check for updates automatically
3. Or use **DreamClipper > Check for Updates...** menu

## Troubleshooting

### "App is damaged" error
The DMG wasn't notarized or stapled. Re-run notarization steps.

### Sparkle doesn't find updates
- Verify `SUFeedURL` in Info.plist matches your appcast location
- Check that appcast.xml is valid XML
- Ensure the version in appcast is higher than installed version

### Signature verification failed
The `sparkle:edSignature` doesn't match. Re-sign the DMG with `sign_update`.
