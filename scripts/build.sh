#!/usr/bin/env bash
# Builds TapDeck.app.
#
#   ./scripts/build.sh --unsigned   Ad-hoc signed app for your own Mac. No Apple account needed. (default)
#   ./scripts/build.sh --release    Developer ID signed, notarized, stapled, with ZIP and DMG.
#
# Nothing in here belongs to anybody in particular. Everything personal comes from the environment:
#
#   TAPDECK_BUNDLE_ID        Reverse-DNS id you control.       default: app.tapdeck.TapDeck
#   TAPDECK_SIGN_IDENTITY    "Developer ID Application: Your Name (TEAMID)"   (release only)
#   TAPDECK_NOTARY_PROFILE   notarytool keychain profile name  (release only)
#   TAPDECK_FEED_URL         https URL of your appcast.xml     (optional, enables update checks)
#   TAPDECK_SPARKLE_KEY      your Sparkle public EdDSA key     (optional, required with FEED_URL)
#
# Without a feed URL and key, update checks stay off. TapDeck never polls somebody else's feed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TapDeck"
BUNDLE_ID="${TAPDECK_BUNDLE_ID:-app.tapdeck.TapDeck}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${TAPDECK_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ENTITLEMENTS="entitlements.plist"
FEED_URL="${TAPDECK_FEED_URL:-}"
SPARKLE_KEY="${TAPDECK_SPARKLE_KEY:-}"
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_LICENSE=".build/artifacts/sparkle/Sparkle/LICENSE"

DIST_DIR="dist"
BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

MODE="unsigned"
case "${1:-}" in
    ""|--unsigned) MODE="unsigned" ;;
    --release) MODE="release" ;;
    --help|-h) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 1 ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
    echo "TapDeck can only be built on macOS." >&2
    exit 1
fi

if [ -n "$FEED_URL" ] || [ -n "$SPARKLE_KEY" ]; then
    if [ -z "$FEED_URL" ] || [ -z "$SPARKLE_KEY" ]; then
        echo "Set both TAPDECK_FEED_URL and TAPDECK_SPARKLE_KEY, or neither." >&2
        exit 1
    fi
    case "$FEED_URL" in https://*) ;; *) echo "TAPDECK_FEED_URL must start with https://" >&2; exit 1 ;; esac
fi

if [ "$MODE" = "release" ]; then
    : "${TAPDECK_SIGN_IDENTITY:?Set TAPDECK_SIGN_IDENTITY for a release build}"
    : "${TAPDECK_NOTARY_PROFILE:?Set TAPDECK_NOTARY_PROFILE for a release build}"
fi

# ── Step 1: Build ──────────────────────────────────────────────
echo "▸ Building $APP_NAME $VERSION (release, arm64)..."
swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)
[ -x "$BIN_DIR/$APP_NAME" ] || { echo "Build produced no $APP_NAME executable." >&2; exit 1; }
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle framework not found at $SPARKLE_FRAMEWORK" >&2; exit 1; }
echo "  ✓ Build complete"

# ── Step 2: Icon ───────────────────────────────────────────────
ICON_FILE=""
if [ ! -f assets/AppIcon.icns ] && [ -f assets/icon-1024.png ]; then
    ./scripts/make-icns.sh
fi
[ -f assets/AppIcon.icns ] && ICON_FILE="AppIcon"

# ── Step 3: Bundle ─────────────────────────────────────────────
echo "▸ Creating $APP_NAME.app..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUNDLE/Contents/Frameworks"
cp "$BIN_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
# Sparkle has versioned symlinks and nested helpers, so copy with ditto.
EMBEDDED_SPARKLE="$BUNDLE/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$EMBEDDED_SPARKLE"
[ -f "$SPARKLE_LICENSE" ] && cp "$SPARKLE_LICENSE" "$BUNDLE/Contents/Resources/Sparkle-LICENSE"
cp LICENSE "$BUNDLE/Contents/Resources/LICENSE"
cp NOTICE.md "$BUNDLE/Contents/Resources/NOTICE.md"
[ -n "$ICON_FILE" ] && cp assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

PLIST="$BUNDLE/Contents/Info.plist"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>TapDeck sends Apple Events only for actions you choose, such as switching dark mode or ejecting drives.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License. See LICENSE.</string>
</dict>
</plist>
PLISTEOF

if [ -n "$ICON_FILE" ]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_FILE" "$PLIST"
fi
if [ -n "$FEED_URL" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $FEED_URL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_KEY" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$PLIST"
    echo "  Updates: on ($FEED_URL)"
else
    echo "  Updates: off (no TAPDECK_FEED_URL / TAPDECK_SPARKLE_KEY given)"
fi
plutil -lint "$PLIST" >/dev/null
echo "  ✓ Bundle created: $BUNDLE"

# ── Unsigned: ad-hoc sign and stop ─────────────────────────────
if [ "$MODE" = "unsigned" ]; then
    codesign --force --deep --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$BUNDLE"
    codesign --verify --deep --strict "$BUNDLE"
    # A simple drag-to-Applications disk image, for installing on your own Mac.
    UNSIGNED_DMG="$DIST_DIR/$APP_NAME-$VERSION-unsigned.dmg"
    rm -f "$UNSIGNED_DMG"
    DMG_STAGE=$(mktemp -d)
    ditto "$BUNDLE" "$DMG_STAGE/$APP_NAME.app"
    ln -s /Applications "$DMG_STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$UNSIGNED_DMG" >/dev/null
    rm -rf "$DMG_STAGE"
    echo ""
    echo "✓ Ready: $BUNDLE and $UNSIGNED_DMG (ad-hoc signed, for this Mac only)"
    echo "  Install: open the DMG and drag TapDeck to Applications. Or run:  open $BUNDLE"
    echo "  If macOS says it cannot be opened: right-click the app, choose Open, then Open again."
    exit 0
fi

# ── Release: sign ──────────────────────────────────────────────
IDENTITY="$TAPDECK_SIGN_IDENTITY"
echo "▸ Signing with: $IDENTITY"
SPARKLE_VERSION="$EMBEDDED_SPARKLE/Versions/Current"
# Innermost code first. Downloader keeps its own sandbox entitlements.
codesign --force --options runtime --sign "$IDENTITY" --timestamp "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign --force --options runtime --preserve-metadata=entitlements --sign "$IDENTITY" --timestamp "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$IDENTITY" --timestamp "$SPARKLE_VERSION/Autoupdate"
codesign --force --options runtime --sign "$IDENTITY" --timestamp "$SPARKLE_VERSION/Updater.app"
codesign --force --options runtime --sign "$IDENTITY" --timestamp "$EMBEDDED_SPARKLE"
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" --timestamp "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
echo "  ✓ Signed"

# ── Release: notarize ──────────────────────────────────────────
echo "▸ Notarizing (a few minutes)..."
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$TAPDECK_NOTARY_PROFILE" --wait
xcrun stapler staple "$BUNDLE"
xcrun stapler validate "$BUNDLE"
# The published ZIP must hold the stapled app.
rm -f "$ZIP"
ditto -c -k --keepParent "$BUNDLE" "$ZIP"
spctl --assess --type exec --verbose "$BUNDLE"
echo "  ✓ Notarized and stapled"

# ── Release: DMG ───────────────────────────────────────────────
echo "▸ Creating DMG..."
rm -f "$DMG"
STAGE=$(mktemp -d)
ditto "$BUNDLE" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$TAPDECK_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "  ✓ DMG ready"

if [ -n "$FEED_URL" ]; then
    echo "▸ Generating the Sparkle appcast..."
    ./scripts/generate-appcast.sh "$ZIP"
fi

echo ""
echo "✓ Release files in $DIST_DIR/: $(basename "$ZIP"), $(basename "$DMG")$( [ -n "$FEED_URL" ] && echo ', appcast.xml')"
echo "  Nothing has been published. Upload them to a GitHub release tagged v$VERSION."
