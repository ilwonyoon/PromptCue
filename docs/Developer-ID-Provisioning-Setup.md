# Developer ID Provisioning Profile Setup for DMG Distribution with iCloud

## About Backtick

Backtick is a macOS menu-bar utility (LSUIElement) for capturing and staging prompts for AI workflows. Users press Cmd+` to capture thoughts, screenshots, and notes, then route them to AI tools like Claude Code, Cursor, or ChatGPT.

- **Product name**: Backtick
- **Bundle ID**: `com.promptcue.promptcue`
- **Code-level name**: PromptCue (temporary technical identifier)
- **CloudKit container**: `iCloud.com.promptcue.promptcue`
- **Distribution**: DMG (direct download), not Mac App Store
- **Key dependency**: iCloud/CloudKit for cross-device sync of captured prompts

## Why This Guide

The DMG release build uses Developer ID signing with Manual code sign style. iCloud/CloudKit entitlements require a provisioning profile. Without it, the archive fails with:

```
"PromptCue" requires a provisioning profile with the iCloud feature.
```

This guide creates and installs that provisioning profile.

## Prerequisites

- Apple Developer account (Team ID: LG7667PAS6)
- Developer ID Application certificate installed in Keychain (SHA1: 1D726853BCB4D54FBF5E2C014EB84DAE24FF6883)
- Access to https://developer.apple.com/account

---

## Step 1: Verify App ID has CloudKit enabled

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Find **com.promptcue.promptcue** in the list
3. Click on it to open details
4. Scroll to **Capabilities** section
5. Verify **iCloud** is checked
   - If not checked: enable it, select **CloudKit**, save
6. Verify **CloudKit** sub-option is selected (not just "Key-value storage")

**Expected result**: App ID shows iCloud with CloudKit enabled.

---

## Step 2: Verify CloudKit Container exists

1. Go to https://developer.apple.com/account/resources/identifiers/list/cloudContainer
2. Look for **iCloud.com.promptcue.promptcue**
   - If it exists: good, continue
   - If not: click **+** → Register a CloudKit Container
     - Description: `Backtick CloudKit Container`
     - Identifier: `iCloud.com.promptcue.promptcue`
     - Click **Continue** → **Register**

**Expected result**: Container `iCloud.com.promptcue.promptcue` exists.

---

## Step 3: Link CloudKit Container to App ID (if not already)

1. Go back to https://developer.apple.com/account/resources/identifiers/list
2. Click on **com.promptcue.promptcue**
3. Scroll to **iCloud** capability
4. Click **Edit** (or **Configure**)
5. Under **CloudKit Containers**, check **iCloud.com.promptcue.promptcue**
6. Click **Continue** → **Save**

**Expected result**: App ID is linked to the CloudKit container.

---

## Step 4: Create Developer ID Provisioning Profile

1. Go to https://developer.apple.com/account/resources/profiles/list
2. Click **+** (Register a New Provisioning Profile)
3. Under **Distribution**, select **Developer ID**
4. Click **Continue**
5. Select App ID: **Backtick (com.promptcue.promptcue)** (or whatever the display name is)
6. Click **Continue**
7. Select Certificate: **Developer ID Application: ILWON YOON (LG7667PAS6)**
8. Click **Continue**
9. Profile Name: `Backtick Developer ID`
10. Click **Generate**
11. Click **Download** — saves as `Backtick_Developer_ID.provisionprofile` (or similar)

**Expected result**: Downloaded `.provisionprofile` file.

---

## Step 5: Install the Provisioning Profile

1. Double-click the downloaded `.provisionprofile` file
   - This installs it to `~/Library/MobileDevice/Provisioning Profiles/`
   - No visible confirmation — it just works silently

2. Verify installation:
```bash
ls ~/Library/MobileDevice/Provisioning\ Profiles/
```
You should see a `.provisionprofile` file with a UUID name.

3. Confirm the profile details:
```bash
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile 2>/dev/null | head -40
```
Look for:
- `com.promptcue.promptcue` in the AppIdentifier
- `iCloud.com.promptcue.promptcue` in the entitlements
- `Developer ID Application` in the certificates

---

## Step 6: Update the Release Build Script

The archive script at `scripts/archive_signed_release.sh` uses `CODE_SIGN_STYLE=Manual`.
For manual signing with a provisioning profile, add the profile specifier to the xcodebuild command.

### Option A: Let Xcode find the profile automatically

In `Config/Release.xcconfig`, add:
```
DEVELOPMENT_TEAM = LG7667PAS6
```

The script already passes `DEVELOPMENT_TEAM` via CLI flag. Xcode should auto-match the installed profile.

### Option B: Specify profile UUID explicitly

1. Get the profile UUID:
```bash
/usr/libexec/PlistBuddy -c 'Print :UUID' /dev/stdin <<< "$(security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/*.provisionprofile 2>/dev/null)"
```

2. Add to `Config/Local.xcconfig`:
```
PROVISIONING_PROFILE_SPECIFIER = Backtick Developer ID
```

Or pass it to the archive script by adding to the xcodebuild command in the script:
```
PROVISIONING_PROFILE_SPECIFIER="Backtick Developer ID"
```

---

## Step 7: Test the DMG Build

```bash
./scripts/archive_signed_release.sh \
  --package-format dmg \
  --team-id LG7667PAS6 \
  --notary-profile backtick-notary \
  --allow-dirty
```

**Expected result**: Archive succeeds, notarization passes, DMG is created at `build/signed-release/`.

---

## Troubleshooting

### "requires a provisioning profile with the iCloud feature"
- Profile not installed, or not linked to the correct App ID
- Run: `ls ~/Library/MobileDevice/Provisioning\ Profiles/` to verify
- Re-download and double-click to reinstall

### "no provisioning profile matches"
- Profile doesn't match the signing certificate or team ID
- Verify the profile was created with the correct Developer ID certificate
- Check that `DEVELOPMENT_TEAM` matches `LG7667PAS6`

### "CloudKit container not found"
- Container `iCloud.com.promptcue.promptcue` not created or not linked
- Go back to Step 2 and Step 3

---

## Summary

After setup, the build pipeline is:

```
archive_signed_release.sh
  → xcodebuild archive (Developer ID + provisioning profile + iCloud)
  → codesign (Developer ID Application certificate)
  → notarytool submit (Apple notarization)
  → stapler staple (attach notarization ticket)
  → hdiutil create (DMG packaging)
  → shasum (checksum)
```

All credentials are stored locally:
- Developer ID cert: Keychain
- Provisioning profile: ~/Library/MobileDevice/Provisioning Profiles/
- Notary credentials: Keychain (backtick-notary profile)
