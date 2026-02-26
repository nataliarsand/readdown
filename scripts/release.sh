#!/bin/bash
set -euo pipefail

# ── Readdown Release Script ──
# Builds, signs, notarizes, and packages Readdown as a DMG.
#
# Usage:
#   ./scripts/release.sh --apple-id you@email.com --password xxxx-xxxx-xxxx-xxxx --team-id XXXXXXXXXX
#   ./scripts/release.sh --skip-notarize   # for local testing

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCHEME="ReadDown"
BUNDLE_ID="com.readdown.app"
APP_NAME="Readdown"
ARCHIVE_PATH="$PROJECT_DIR/release/${SCHEME}.xcarchive"
EXPORT_PATH="$PROJECT_DIR/release/export"
DMG_PATH="$PROJECT_DIR/release/${APP_NAME}.dmg"

APPLE_ID=""
APP_PASSWORD=""
TEAM_ID=""
SKIP_NOTARIZE=false

# ── Parse arguments ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apple-id)    APPLE_ID="$2"; shift 2 ;;
        --password)    APP_PASSWORD="$2"; shift 2 ;;
        --team-id)     TEAM_ID="$2"; shift 2 ;;
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$SKIP_NOTARIZE" = false ] && { [ -z "$APPLE_ID" ] || [ -z "$APP_PASSWORD" ] || [ -z "$TEAM_ID" ]; }; then
    echo "Error: --apple-id, --password, and --team-id are required (or use --skip-notarize)"
    exit 1
fi

# ── Clean previous build ──

echo "==> Cleaning previous release artifacts..."
rm -rf "$PROJECT_DIR/release"
mkdir -p "$PROJECT_DIR/release"

# ── Step 1: Archive ──

echo "==> Archiving..."
xcodebuild archive \
    -project "$PROJECT_DIR/${SCHEME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application"

# ── Step 2: Export ──

echo "==> Exporting..."
EXPORT_OPTIONS="$PROJECT_DIR/release/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -quiet

APP_PATH="$EXPORT_PATH/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    # Sometimes the exported app name matches the scheme
    APP_PATH="$EXPORT_PATH/${SCHEME}.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Could not find exported .app in $EXPORT_PATH"
    ls -la "$EXPORT_PATH"
    exit 1
fi

# ── Step 3: Verify code signature ──

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    Signature OK."

# ── Step 4: Notarize ──

if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing..."
    NOTARIZE_ZIP="$PROJECT_DIR/release/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    rm -f "$NOTARIZE_ZIP"

    # ── Step 5: Staple ──

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
else
    echo "==> Skipping notarization (--skip-notarize)"
fi

# ── Step 6: Create DMG ──

echo "==> Creating DMG..."
DMG_STAGING="$PROJECT_DIR/release/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

# ── Step 7: Sign the DMG ──

echo "==> Signing DMG..."
codesign --sign "Developer ID Application" "$DMG_PATH"

# ── Done ──

echo ""
echo "==> Release complete!"
echo "    DMG: $DMG_PATH"
echo ""
echo "To upload to GitHub Releases:"
echo "    gh release create v1.0 --title \"Readdown 1.0\" \"$DMG_PATH\""
