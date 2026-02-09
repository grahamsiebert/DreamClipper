# DreamClipper Installation Guide

## Step 1: Download

Download the latest version from the [Releases page](https://github.com/grahamsiebert/DreamClipper/releases/latest).

Click on **DreamClipper-X.X.X.dmg** to download.

---

## Step 2: Open the DMG

Double-click the downloaded `.dmg` file to mount it.

You'll see a window with the DreamClipper app and an Applications folder shortcut.

**Drag DreamClipper into the Applications folder.**

<!-- ![Drag to Applications](images/install-drag.png) -->

---

## Step 3: First Launch - Security Warning

When you first open DreamClipper, macOS will show a security warning:

> "DreamClipper" Not Opened
> Apple could not verify "DreamClipper" is free of malware...

**This is normal.** The app is safe but not yet notarized with Apple.

<!-- ![Security Warning](images/install-warning.png) -->

**Click "Done"** (not "Move to Trash").

---

## Step 4: Allow the App to Open

1. Open **System Settings** (click the Apple menu → System Settings)

2. Go to **Privacy & Security** (in the left sidebar)

3. Scroll down to the **Security** section

4. You'll see: _"DreamClipper" was blocked from use because it is not from an identified developer._

5. Click **Open Anyway**

<!-- ![Open Anyway](images/install-open-anyway.png) -->

6. Enter your Mac password if prompted

7. Click **Open** in the confirmation dialog

---

## Step 5: Grant Permissions

DreamClipper needs two permissions to work:

### Screen Recording Permission

When you first try to record, macOS will ask for Screen Recording permission.

1. Click **Open System Settings** when prompted
2. Toggle on **DreamClipper** in the Screen Recording list
3. Restart DreamClipper if needed

<!-- ![Screen Recording Permission](images/install-screen-recording.png) -->

### Accessibility Permission (for window resizing)

When you click "Resize Window", macOS may ask for Accessibility permission.

1. Click **Open System Settings** when prompted
2. Toggle on **DreamClipper** in the Accessibility list

---

## Done!

DreamClipper is now installed and ready to use.

**To create a GIF:**
1. Select a window to record
2. Click Record and perform your actions
3. Click Stop when finished
4. Trim if needed, adjust settings, and export your GIF

---

## Troubleshooting

### "App is damaged and can't be opened"
Run this command in Terminal:
```bash
xattr -cr /Applications/DreamClipper.app
```
Then try opening the app again.

### App doesn't appear in Screen Recording settings
Restart your Mac and try again.

### Updates
DreamClipper checks for updates automatically. You can also check manually via the menu: **DreamClipper → Check for Updates...**
