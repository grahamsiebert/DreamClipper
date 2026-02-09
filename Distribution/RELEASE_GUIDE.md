# DreamClipper Direct Distribution Guide

This guide walks you through releasing DreamClipper outside the Mac App Store.

## Prerequisites

1. **Apple Developer Account** ($99/year)
2. **Developer ID Application certificate** (for code signing)
3. **App-specific password** (for notarization)

---

## One-Time Setup

### 1. Generate Sparkle EdDSA Keys

Sparkle uses EdDSA signatures for secure updates. Generate your keys:

```bash
# Download Sparkle tools
cd /tmp
curl -L -o Sparkle-2.6.4.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
tar -xf Sparkle-2.6.4.tar.xz
cd Sparkle-2.6.4

# Generate keys (this creates ~/.sparkle_eddsa_key)
./bin/generate_keys
```

**IMPORTANT:** This will output a **public key**. Copy it and update `Info.plist`:
```xml
<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_KEY_HERE</string>
```

The private key is stored in `~/.sparkle_eddsa_key` - **back this up securely!**

### 2. Store Notarization Credentials

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "your@email.com" \
    --team-id "922D33U8V6" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

To create an app-specific password:
1. Go to https://appleid.apple.com
2. Sign In → Security → App-Specific Passwords
3. Generate a new password for "DreamClipper Notarization"

### 3. Update Info.plist with Your Domain

Edit `Info.plist` and set your actual appcast URL:
```xml
<key>SUFeedURL</key>
<string>https://yourdomain.com/appcast.xml</string>
```

---

## Release Process

### Step 1: Update Version Numbers

Edit `Info.plist`:
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>  <!-- User-facing version -->
<key>CFBundleVersion</key>
<string>1</string>       <!-- Build number - increment each release -->
```

### Step 2: Build, Sign & Notarize

```bash
cd /Users/a.graham/DreamClipper/Distribution
./build-release.sh 1.0.0
```

This will:
1. Archive the app
2. Export with Developer ID signing
3. Notarize with Apple
4. Create a DMG
5. Notarize the DMG

### Step 3: Sign the DMG for Sparkle

```bash
/tmp/Sparkle-2.6.4/bin/sign_update "/Users/a.graham/DreamClipper/build/DreamClipper-1.0.0.dmg"
```

This outputs an `edSignature` - copy it for the appcast.

### Step 4: Update appcast.xml

Edit `Distribution/appcast.xml`:

```xml
<item>
    <title>Version 1.0.0</title>
    <description><![CDATA[
        <h2>What's New</h2>
        <ul>
            <li>Your release notes here</li>
        </ul>
    ]]></description>
    <pubDate>Thu, 06 Feb 2026 12:00:00 +0000</pubDate>
    <sparkle:version>1</sparkle:version>
    <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
    <enclosure
        url="https://yourdomain.com/releases/DreamClipper-1.0.0.dmg"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"
        length="12345678"
        type="application/octet-stream" />
</item>
```

Get the file size:
```bash
stat -f%z "/Users/a.graham/DreamClipper/build/DreamClipper-1.0.0.dmg"
```

### Step 5: Upload to Server

Upload these files to your web server:
- `DreamClipper-1.0.0.dmg` → `https://yourdomain.com/releases/`
- `appcast.xml` → `https://yourdomain.com/`

---

## Hosting Options

### Option A: GitHub Releases (Free)
1. Create a GitHub repo
2. Upload DMG as a release asset
3. Host appcast.xml in the repo or use GitHub Pages
4. Update URLs accordingly

### Option B: Your Own Server
- Any static file hosting works (S3, Cloudflare R2, Netlify, etc.)
- Ensure HTTPS is enabled

### Option C: Simple Web Host
- Vercel, Netlify, or any static hosting
- Just upload the DMG and appcast.xml

---

## Checklist for Each Release

- [ ] Update version in `Info.plist` (both CFBundleShortVersionString and CFBundleVersion)
- [ ] Run `./build-release.sh X.Y.Z`
- [ ] Sign DMG with Sparkle: `sign_update "path/to/dmg"`
- [ ] Update `appcast.xml` with new version, signature, and file size
- [ ] Upload DMG to server
- [ ] Upload appcast.xml to server
- [ ] Test update by running previous version

---

## Testing Updates

1. Install the previous version
2. Launch it - it should find the update
3. Or manually: DreamClipper menu → Check for Updates...

---

## Troubleshooting

### "App is damaged and can't be opened"
- App wasn't notarized or stapled properly
- Re-run notarization and stapling

### Updates not showing
- Check SUFeedURL in Info.plist matches your server
- Verify appcast.xml is accessible (curl the URL)
- Check version numbers: new version must be higher

### Code signing issues
- Ensure you have "Developer ID Application" certificate
- Check Keychain Access for valid certificates

---

## Files Created

```
Distribution/
├── RELEASE_GUIDE.md     # This file
├── appcast.xml          # Update feed template
└── build-release.sh     # Automated build script
```
