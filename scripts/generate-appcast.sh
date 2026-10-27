#!/usr/bin/env bash
# Creates dist/appcast.xml for a signed, notarized release ZIP.
#
#   TAPDECK_REPO             "owner/repo" on GitHub that hosts the releases   (required)
#   TAPDECK_SPARKLE_ACCOUNT  Keychain account holding your Sparkle private key (default: tapdeck)
#
# One-time setup: run  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account tapdeck
# It prints your public key. Put that key in TAPDECK_SPARKLE_KEY and in sparkle-public-key.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    sed -n '2,9p' "$0"
    echo "Usage: $0 dist/TapDeck-<version>.zip"
    [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && exit 0
    exit 1
fi

ARCHIVE="$1"
: "${TAPDECK_REPO:?Set TAPDECK_REPO, for example your-name/TapDeck}"
ACCOUNT="${TAPDECK_SPARKLE_ACCOUNT:-tapdeck}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
RELEASE_BASE_URL="https://github.com/$TAPDECK_REPO/releases"

[ -f "$ARCHIVE" ] || { echo "Missing $ARCHIVE" >&2; exit 1; }
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Sparkle tools missing. Run ./scripts/build.sh first." >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/archives" "$STAGE/extracted"
cp "$ARCHIVE" "$STAGE/archives/"
ditto -x -k "$ARCHIVE" "$STAGE/extracted"
APP="$STAGE/extracted/Bango.app"
PLIST="$APP/Contents/Info.plist"

# Read metadata from the exact bytes people will download.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a version like 1.0.0, found $VERSION" >&2; exit 1; }
KEYCHAIN_KEY=$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)
if [ "$PUBLIC_KEY" != "$KEYCHAIN_KEY" ]; then
    echo "The app's SUPublicEDKey does not match the key in Keychain account '$ACCOUNT'." >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"

"$SPARKLE_BIN/generate_appcast" \
    --account "$ACCOUNT" \
    --download-url-prefix "$RELEASE_BASE_URL/download/v$VERSION/" \
    --link "$RELEASE_BASE_URL/tag/v$VERSION" \
    --maximum-deltas 0 \
    -o "$STAGE/appcast.xml" \
    "$STAGE/archives"
mkdir -p dist
cp "$STAGE/appcast.xml" dist/appcast.xml
echo "✓ dist/appcast.xml is ready for v$VERSION. Upload it to the release as appcast.xml."
