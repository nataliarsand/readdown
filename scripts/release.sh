#!/bin/bash
set -euo pipefail

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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "==> Cleaning previous release artifacts..."
rm -rf "$PROJECT_DIR/release"
mkdir -p "$PROJECT_DIR/release"

echo "==> Archiving..."
xcodebuild archive \
    -project "$PROJECT_DIR/${SCHEME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application"

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

# macOS 15 refuses app extensions and Sparkle XPC services stamped sdk 26.x; rewrite to 15.0, then re-sign.

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

# Only the QL extension and Sparkle binaries are patched. The main app must keep its SDK 26 stamp or AppKit drops the Tahoe chrome.
patch_sdk "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex/Contents/MacOS/ReadDownQuickLook"

SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
patch_sdk "$SPARKLE_FW/Sparkle"
patch_sdk "$SPARKLE_FW/Autoupdate"
patch_sdk "$SPARKLE_FW/Updater.app/Contents/MacOS/Updater"
patch_sdk "$SPARKLE_FW/XPCServices/Installer.xpc/Contents/MacOS/Installer"
patch_sdk "$SPARKLE_FW/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"

# Innermost first. codesign --force wipes entitlements unless --entitlements is passed.
echo "==> Re-signing after SDK patch..."
codesign --force --sign "Developer ID Application" --options runtime \
    "$SPARKLE_FW/Autoupdate"
codesign --force --sign "Developer ID Application" --options runtime \
    "$SPARKLE_FW/XPCServices/Installer.xpc"
codesign --force --sign "Developer ID Application" --options runtime \
    "$SPARKLE_FW/XPCServices/Downloader.xpc"
codesign --force --sign "Developer ID Application" --options runtime \
    "$SPARKLE_FW/Updater.app"
codesign --force --sign "Developer ID Application" --options runtime \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "Developer ID Application" --options runtime \
    --entitlements "$PROJECT_DIR/ReadDownQuickLook/ReadDownQuickLook.entitlements" \
    "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex"
codesign --force --sign "Developer ID Application" --options runtime \
    --entitlements "$PROJECT_DIR/Sources/ReadDown.entitlements" \
    "$APP_PATH"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    Signature OK."

if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing..."
    NOTARIZE_ZIP="$PROJECT_DIR/release/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    rm -f "$NOTARIZE_ZIP"

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
else
    echo "==> Skipping notarization (--skip-notarize)"
fi

echo "==> Validating release..."
"$SCRIPT_DIR/validate-release.sh" "$APP_PATH"

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

echo "==> Signing DMG..."
codesign --sign "Developer ID Application" "$DMG_PATH"

# Gatekeeper checks the DMG itself on a manual download; a stapled app inside is not enough.

if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "==> Stapling DMG..."
    xcrun stapler staple "$DMG_PATH"
fi

# Sparkle can only install from a zip, never a DMG.

echo "==> Creating Sparkle zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Generating Sparkle appcast entry..."

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

    # Release notes for the Sparkle dialog: the CHANGELOG section for VERSION, up to "### Details", as HTML.
    CHANGELOG_PATH="$PROJECT_DIR/CHANGELOG.md"
    HIGHLIGHTS=""
    if [ -f "$CHANGELOG_PATH" ]; then
        HIGHLIGHTS=$(awk -v ver="$VERSION" '
            function esc(s) {
                gsub(/&/, "\\&amp;", s)
                gsub(/</, "\\&lt;", s)
                gsub(/>/, "\\&gt;", s)
                return s
            }
            function md_inline(s,    out, i, ch, in_code) {
                s = esc(s)
                out = ""; in_code = 0
                for (i = 1; i <= length(s); i++) {
                    ch = substr(s, i, 1)
                    if (ch == "`") {
                        out = out (in_code ? "</code>" : "<code>")
                        in_code = !in_code
                    } else { out = out ch }
                }
                if (in_code) { out = out "</code>" }
                return out
            }
            /^## / {
                if (found) { exit }
                if ($2 == ver) { found = 1 }
                next
            }
            found {
                if (/^## /) { exit }
                if (/^### Details/) { exit }
                if (/^### /) {
                    if (in_list) { print "</ul>"; in_list = 0 }
                    sub(/^### /, "")
                    print "<h4>" esc($0) "</h4>"
                    next
                }
                if (/^- /) {
                    if (!in_list) { print "<ul>"; in_list = 1 }
                    sub(/^- /, "")
                    printf "<li>%s</li>\n", md_inline($0)
                    next
                }
                if (NF == 0) {
                    if (in_list) { print "</ul>"; in_list = 0 }
                    next
                }
                if (in_list) { print "</ul>"; in_list = 0 }
                print "<p>" md_inline($0) "</p>"
            }
            END { if (in_list) print "</ul>" }
        ' "$CHANGELOG_PATH")
    fi

    if [ -z "$HIGHLIGHTS" ]; then
        echo "    WARNING: No CHANGELOG.md entry found for version $VERSION — appcast will have no release notes."
        DESCRIPTION_TAG=""
    else
        FULL_NOTES_LINK="<p style=\"margin-top:12px;font-size:12px;\"><a href=\"https://readdown.app/#changelog\">See full release notes</a></p>"
        DESCRIPTION_TAG="            <description><![CDATA[${HIGHLIGHTS}${FULL_NOTES_LINK}]]></description>"
    fi

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
            <sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>
${DESCRIPTION_TAG}
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

# Leftover .app bundles show up in Spotlight.

rm -rf "$EXPORT_PATH" "$ARCHIVE_PATH"

echo ""
echo "==> Release complete!"
echo "    DMG: $DMG_PATH"
echo "    ZIP: $ZIP_PATH"
echo ""
echo "To upload to GitHub Releases:"
echo "    gh release create v${VERSION:-X.Y} --title \"Readdown ${VERSION:-X.Y}\" \"$DMG_PATH\" \"$ZIP_PATH\""
echo ""
echo "Then deploy appcast.xml to the website:"
echo "    cp $PROJECT_DIR/release/appcast.xml ~/Dev/readdown-website/public/data/appcast.xml"
echo "    cd ~/Dev/readdown-website && git add public/data/appcast.xml && git commit -m 'Update appcast for v${VERSION:-X.Y}' && git push"
echo ""
echo "    # /appcast.xml is served by functions/appcast.xml.js which logs"
echo "    # Sparkle profile params then proxies the static /data/appcast.xml."
