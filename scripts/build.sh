#!/usr/bin/env bash
# Builds Bingo.app.
#
#   ./scripts/build.sh --unsigned   Ad-hoc signed app for your own Mac. No Apple account needed. (default)
#   ./scripts/build.sh --release    Developer ID signed, notarized, stapled, with ZIP and DMG.
#
# Nothing in here belongs to anybody in particular. Everything personal comes from the environment:
#
#   TAPDECK_BUNDLE_ID        Reverse-DNS id you control.       default: app.bingo.Bingo
#   TAPDECK_SIGN_IDENTITY    "Developer ID Application: Your Name (TEAMID)"   (release only)
#   TAPDECK_NOTARY_PROFILE   notarytool keychain profile name  (release only)
#   TAPDECK_FEED_URL         https URL of your appcast.xml     (optional, enables update checks)
#   TAPDECK_SPARKLE_KEY      your Sparkle public EdDSA key     (optional, required with FEED_URL)
#
# Without a feed URL and key, update checks stay off. Bingo never polls somebody else's feed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Bingo"
BIN_NAME="TapDeck"   # the SwiftPM executable; only the app bundle carries the product name
BUNDLE_ID="${TAPDECK_BUNDLE_ID:-app.bingo.Bingo}"
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
    echo "Bingo can only be built on macOS." >&2
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


# ── Disk image ─────────────────────────────────────────────────
# A drag-to-Applications window with a background and an arrow. It needs the create-dmg tool
# (brew install create-dmg) and a Finder session. If either is missing or styling fails, a plain
# disk image is made instead, so the build never fails because of the artwork.
make_dmg() {
    local output="$1"
    local stage
    stage=$(mktemp -d)
    ditto "$BUNDLE" "$stage/$APP_NAME.app"
    rm -f "$output"

    local styled=0
    if command -v create-dmg >/dev/null 2>&1 && [ -f assets/dmg-background@2x.png ]; then
        local art
        art=$(mktemp -d)
        cp assets/dmg-background@2x.png "$art/bg@2x.png"
        sips -s dpiWidth 144 -s dpiHeight 144 "$art/bg@2x.png" >/dev/null 2>&1 || true
        sips -z 400 660 -s dpiWidth 72 -s dpiHeight 72 assets/dmg-background@2x.png --out "$art/bg.png" >/dev/null 2>&1 || true
        local background="$art/bg.png"
        if tiffutil -cathidpicheck "$art/bg.png" "$art/bg@2x.png" -out "$art/bg.tiff" >/dev/null 2>&1; then
            background="$art/bg.tiff"
        fi
        if create-dmg \
            --volname "$APP_NAME" \
            --background "$background" \
            --window-pos 200 120 \
            --window-size 660 400 \
            --icon-size 128 \
            --text-size 13 \
            --icon "$APP_NAME.app" 180 190 \
            --hide-extension "$APP_NAME.app" \
            --app-drop-link 480 190 \
            --no-internet-enable \
            "$output" "$stage" >/dev/null 2>&1 && [ -f "$output" ]; then
            styled=1
            echo "  ✓ Disk image with the drag-to-Applications window"
        else
            echo "  ! create-dmg did not finish. Making a plain disk image instead." >&2
            rm -f "$output"
        fi
        rm -rf "$art"
    fi

    if [ "$styled" = 0 ]; then
        ln -s /Applications "$stage/Applications"
        hdiutil create -volname "$APP_NAME" -srcfolder "$stage" -ov -format UDZO "$output" >/dev/null
    fi
    rm -rf "$stage"
}

# ── Step 1: Build ──────────────────────────────────────────────
echo "▸ Building $APP_NAME $VERSION (release, arm64)..."
swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)
[ -x "$BIN_DIR/$BIN_NAME" ] || { echo "Build produced no $BIN_NAME executable." >&2; exit 1; }
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
cp "$BIN_DIR/$BIN_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
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
    <string>Bingo sends Apple Events only for actions you choose, such as switching dark mode or ejecting drives.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Bingo listens only between the two double taps of dictation, to turn your speech into text on this Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Bingo uses on-device speech recognition to turn what you say into text. The audio does not leave this Mac.</string>
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
    # A drag-to-Applications disk image, for installing on your own Mac.
    UNSIGNED_DMG="$DIST_DIR/$APP_NAME-$VERSION-unsigned.dmg"
    make_dmg "$UNSIGNED_DMG"
    echo ""
    echo "✓ Ready: $BUNDLE and $UNSIGNED_DMG (ad-hoc signed, for this Mac only)"
    echo "  Install: open the DMG and drag Bingo to Applications. Or run:  open $BUNDLE"
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
make_dmg "$DMG"
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
