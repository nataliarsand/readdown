#!/bin/bash
set -euo pipefail

# ── Readdown Release Script ──
# Builds, signs, notarizes, and packages Readdown as a DMG.
#
# Usage:
#   ./scripts/release.sh                           # uses keychain profile "Readdown"
#   ./scripts/release.sh --skip-notarize           # for local testing
#
# To set up keychain credentials (one-time):
#   xcrun notarytool store-credentials "Readdown" --apple-id you@email.com --team-id XXXXXXXXXX

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCHEME="ReadDown"
BUNDLE_ID="com.heya.readdown"
APP_NAME="Readdown"
KEYCHAIN_PROFILE="Readdown"
ARCHIVE_PATH="$PROJECT_DIR/release/${SCHEME}.xcarchive"
EXPORT_PATH="$PROJECT_DIR/release/export"
DMG_PATH="$PROJECT_DIR/release/${APP_NAME}.dmg"
ZIP_PATH="$PROJECT_DIR/release/${APP_NAME}.zip"

SKIP_NOTARIZE=false

# ── Parse arguments ──

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

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

# ── Step 3: Patch SDK version ──
# Xcode 26 beta stamps sdk 26.x into binaries, which causes macOS 15 to
# refuse registering app extensions. Rewrite to sdk 15.0 after export,
# then re-sign so the patched binaries have valid signatures.

echo "==> Patching SDK version..."
patch_sdk() {
    local binary="$1"
    if vtool -show "$binary" 2>/dev/null | grep -q 'sdk 2[6-9]'; then
        local minos
        minos=$(vtool -show "$binary" 2>/dev/null | grep "minos " | head -1 | awk '{print $2}')
        vtool -set-build-version macos "${minos:-13.0}" 15.0 -replace -output "${binary}.tmp" "$binary"
        mv "${binary}.tmp" "$binary"
        echo "    Patched: $(basename "$(dirname "$(dirname "$binary")")")/$(basename "$binary")"
    else
        echo "    OK (no patch needed): $(basename "$binary")"
    fi
}

# Patch QL extension first (inner), then main app (outer)
patch_sdk "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex/Contents/MacOS/ReadDownQuickLook"
patch_sdk "$APP_PATH/Contents/MacOS/ReadDown"

# Re-sign after patching (extension first, then app)
# IMPORTANT: must pass --entitlements to preserve them after re-signing
echo "==> Re-signing after SDK patch..."
codesign --force --sign "Developer ID Application" --options runtime \
    --entitlements "$PROJECT_DIR/ReadDownQuickLook/ReadDownQuickLook.entitlements" \
    "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex"
codesign --force --sign "Developer ID Application" --options runtime \
    --entitlements "$PROJECT_DIR/Sources/ReadDown.entitlements" \
    "$APP_PATH"

# ── Step 4: Verify code signature ──

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    Signature OK."

# ── Step 5: Notarize ──

if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing..."
    NOTARIZE_ZIP="$PROJECT_DIR/release/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    rm -f "$NOTARIZE_ZIP"

    # ── Step 6: Staple ──

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
else
    echo "==> Skipping notarization (--skip-notarize)"
fi

# ── Step 7: Validate release ──

echo "==> Validating release..."
"$SCRIPT_DIR/validate-release.sh" "$APP_PATH"

# ── Step 8: Create DMG ──

echo "==> Creating DMG..."
rm -f "$DMG_PATH"

create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 160 \
    --icon "$APP_NAME.app" 180 170 \
    --app-drop-link 480 170 \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

# ── Step 9: Sign the DMG ──

echo "==> Signing DMG..."
codesign --sign "Developer ID Application" "$DMG_PATH"

# ── Step 10: Create Sparkle zip ──
# Sparkle auto-updates require a zip (not DMG). DMG is for manual downloads.

echo "==> Creating Sparkle zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── Step 11: Generate Sparkle appcast ──

echo "==> Generating Sparkle appcast entry..."

# Find Sparkle tools from SPM
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/ReadDown-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)"
if [ -z "$SPARKLE_BIN" ] || [ ! -f "$SPARKLE_BIN/sign_update" ]; then
    echo "    WARNING: Sparkle tools not found. Skipping appcast generation."
    echo "    Run 'xcodebuild -resolvePackageDependencies' first."
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
    BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist")
    SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>&1)
    SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    ZIP_SIZE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
    ZIP_URL="https://github.com/nataliarsand/readdown/releases/download/v${VERSION}/Readdown.zip"

    APPCAST_PATH="$PROJECT_DIR/release/appcast.xml"
    cat > "$APPCAST_PATH" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Readdown Updates</title>
        <link>https://heya.studio/readdown/appcast.xml</link>
        <language>en</language>
        <item>
            <title>Readdown ${VERSION}</title>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="${ZIP_URL}"
                       length="${ZIP_SIZE}"
                       type="application/octet-stream"
                       sparkle:edSignature="${SIGNATURE}" />
        </item>
    </channel>
</rss>
APPCAST

    echo "    Appcast: $APPCAST_PATH"
    echo "    Version: $VERSION (build $BUILD)"
fi

# ── Step 12: Clean intermediate artifacts ──
# Remove export folder and archive so only DMG and zip remain.
# Prevents stale .app bundles from appearing in Spotlight.

rm -rf "$EXPORT_PATH" "$ARCHIVE_PATH"

# ── Done ──

echo ""
echo "==> Release complete!"
echo "    DMG: $DMG_PATH"
echo "    ZIP: $ZIP_PATH"
echo ""
echo "To upload to GitHub Releases:"
echo "    gh release create v${VERSION:-X.Y} --title \"Readdown ${VERSION:-X.Y}\" \"$DMG_PATH\" \"$ZIP_PATH\""
echo ""
echo "Then deploy appcast.xml to your website:"
echo "    cp $PROJECT_DIR/release/appcast.xml ~/Dev/heya-studio/readdown/appcast.xml"
