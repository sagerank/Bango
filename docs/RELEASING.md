# Releasing

Only the maintainer builds signed releases, with their own Apple Developer ID. Public CI builds unsigned only.

## One-time setup

1. An Apple Developer Program membership and a **Developer ID Application** certificate in your Keychain
2. A notarization profile:
   ```sh
   xcrun notarytool store-credentials tapdeck-notary --apple-id you@example.com --team-id TEAMID
   ```
3. A bundle identifier you own, for example `com.yourname.Bango`. Do not change it between releases: permissions and the login item are tied to it
4. Optional, for automatic updates: a Sparkle key pair
   ```sh
   swift build            # fetches Sparkle
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account tapdeck
   ```
   It prints the public key. The private key stays in your Keychain. Never commit it

## Each release

1. Update `VERSION` and `CHANGELOG.md`, run `swift test`
2. Build:
   ```sh
   export TAPDECK_BUNDLE_ID=com.yourname.TapDeck
   export TAPDECK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
   export TAPDECK_NOTARY_PROFILE=tapdeck-notary
   # only with updates:
   export TAPDECK_FEED_URL=https://github.com/you/TapDeck/releases/latest/download/appcast.xml
   export TAPDECK_SPARKLE_KEY=<public key>
   export TAPDECK_REPO=you/TapDeck
   ./scripts/build.sh --release
   ```
3. Check `dist/Bango-<version>.zip` on a second Mac: it opens with no warning and taps work
4. Create a GitHub release tagged `v<version>` and upload the ZIP, the DMG and `appcast.xml`

Nothing in the scripts publishes anything.

## Why not the Mac App Store

The sensor is read through an undocumented system interface. App Store review does not allow private APIs, and the App Sandbox blocks the access. Direct download with Developer ID and notarization is the supported route.
