#!/bin/bash
set -euo pipefail

# Validates a Readdown release build to catch common issues
# before shipping. Run against the exported .app bundle.

APP_PATH="${1:-}"

if [ -z "$APP_PATH" ]; then
    echo "Usage: $0 <path-to-Readdown.app>"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "FAIL: App not found at $APP_PATH"
    exit 1
fi

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "==> Validating $APP_PATH"
echo ""

# ── SDK Version ──
echo "--- SDK Version (vtool) ---"

check_sdk() {
    local binary="$1"
    local label="$2"
    local sdk_ver
    sdk_ver=$(vtool -show "$binary" 2>/dev/null | grep "sdk " | head -1 | awk '{print $2}')
    local major="${sdk_ver%%.*}"
    if [ -n "$major" ] && [ "$major" -le 15 ] 2>/dev/null; then
        echo "  PASS: $label SDK version is $sdk_ver"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label SDK version is $sdk_ver (expected <= 15.x)"
        FAIL=$((FAIL + 1))
    fi
}

check_sdk "$APP_PATH/Contents/MacOS/ReadDown" "Main app"
check_sdk "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex/Contents/MacOS/ReadDownQuickLook" "Quick Look extension"

# ── Quick Look Extension Bundle ──
echo ""
echo "--- Quick Look Extension ---"

check "QL appex exists" test -d "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex"
check "QL binary exists" test -x "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex/Contents/MacOS/ReadDownQuickLook"

# Verify QL Info.plist has correct structure
QL_PLIST="$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex/Contents/Info.plist"
check "QL Info.plist exists" test -f "$QL_PLIST"
check "QL extension point in NSExtension" \
    /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$QL_PLIST"
check "QL supported content types in NSExtensionAttributes" \
    /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:0" "$QL_PLIST"

QL_UTI0=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:0" "$QL_PLIST" 2>/dev/null || echo "")
QL_UTI1=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:1" "$QL_PLIST" 2>/dev/null || echo "")
if [ "$QL_UTI0" = "net.daringfireball.markdown" ]; then
    echo "  PASS: QL UTI includes net.daringfireball.markdown"
    PASS=$((PASS + 1))
else
    echo "  FAIL: QL UTI[0] is '$QL_UTI0' (expected net.daringfireball.markdown)"
    FAIL=$((FAIL + 1))
fi
if [ "$QL_UTI1" = "public.markdown" ]; then
    echo "  PASS: QL UTI includes public.markdown"
    PASS=$((PASS + 1))
else
    echo "  FAIL: QL UTI[1] is '$QL_UTI1' (expected public.markdown)"
    FAIL=$((FAIL + 1))
fi

# ── Code Signing ──
echo ""
echo "--- Code Signing ---"

check "Main app signature valid" codesign --verify --deep --strict "$APP_PATH"
check "QL extension signature valid" codesign --verify --strict "$APP_PATH/Contents/PlugIns/ReadDownQuickLook.appex"

SIGNING_ID=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority=Developer ID Application" | head -1 || echo "")
if [ -n "$SIGNING_ID" ]; then
    echo "  PASS: Signed with Developer ID"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Not signed with Developer ID Application"
    FAIL=$((FAIL + 1))
fi

# ── App Info.plist ──
echo ""
echo "--- App Info.plist ---"

APP_PLIST="$APP_PATH/Contents/Info.plist"
check "App Info.plist exists" test -f "$APP_PLIST"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PLIST" 2>/dev/null || echo "")
if [ "$BUNDLE_ID" = "com.heya.readdown" ]; then
    echo "  PASS: Bundle ID is com.heya.readdown"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Bundle ID is '$BUNDLE_ID' (expected com.heya.readdown)"
    FAIL=$((FAIL + 1))
fi

# ── Universal Binary ──
echo ""
echo "--- Architecture ---"

ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/ReadDown" 2>/dev/null || echo "")
if echo "$ARCHS" | grep -q "arm64" && echo "$ARCHS" | grep -q "x86_64"; then
    echo "  PASS: Universal binary (arm64 + x86_64)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Not universal binary (got: $ARCHS)"
    FAIL=$((FAIL + 1))
fi

# ── Summary ──
echo ""
echo "==> Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    echo "==> RELEASE VALIDATION FAILED"
    exit 1
else
    echo "==> All checks passed"
fi
