#!/usr/bin/env bash
# scripts/release.sh — Build, sign, notarize, and package TouchpadInput.app
#
# Prerequisites:
#   - Xcode command line tools + Xcode active toolchain
#   - Apple Developer ID Application certificate in Keychain
#   - NOTARIZE_APPLE_ID, NOTARIZE_TEAM_ID, NOTARIZE_PASSWORD env vars
#     (NOTARIZE_PASSWORD should be an app-specific password from appleid.apple.com)
#
# Usage:
#   ./scripts/release.sh [version]       # e.g. ./scripts/release.sh 1.0.0
#   VERSION=1.0.0 ./scripts/release.sh

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

APP_NAME="TouchpadInput"
BUNDLE_ID="com.touchpad-input.app"
EXECUTABLE="TouchpadInputApp"
VERSION="${1:-${VERSION:-1.0.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
STAGING_DIR="$REPO_ROOT/.build/staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
OUTPUT_DIR="$REPO_ROOT/release"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
ENTITLEMENTS="$REPO_ROOT/Sources/TouchpadInputApp/TouchpadInputApp.entitlements"
INFO_PLIST="$REPO_ROOT/Sources/TouchpadInputApp/Info.plist"

# ── Helpers ───────────────────────────────────────────────────────────────────

info()  { echo "▸ $*"; }
error() { echo "✗ $*" >&2; exit 1; }

require_env() {
    for var in "$@"; do
        [[ -n "${!var:-}" ]] || error "Required env var \$$var is not set."
    done
}

# ── 1. Preflight ──────────────────────────────────────────────────────────────

info "TouchpadInput release script — v${VERSION} (build ${BUILD_NUMBER})"

require_env NOTARIZE_APPLE_ID NOTARIZE_TEAM_ID NOTARIZE_PASSWORD

# Verify signing identity exists in Keychain
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    error "No certificate matching '$SIGN_IDENTITY' found in Keychain."
fi

# ── 2. Build ──────────────────────────────────────────────────────────────────

info "Building (release)…"
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
cd "$REPO_ROOT"
swift build -c release 2>&1 | grep -v "^Build complete"
info "Build complete."

# ── 3. Assemble .app bundle ───────────────────────────────────────────────────

info "Assembling $APP_NAME.app…"
rm -rf "$STAGING_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Binary
cp "$BUILD_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

# Info.plist — stamp version + build number
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"       "$CONTENTS/Info.plist"

info "Bundle structure ready."

# ── 4. Code sign ──────────────────────────────────────────────────────────────

info "Signing with '$SIGN_IDENTITY'…"
codesign \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    --force \
    --deep \
    "$APP_BUNDLE"

info "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 || true  # may fail pre-notarization

# ── 5. Notarize ───────────────────────────────────────────────────────────────

info "Creating zip for notarization…"
ZIP_PATH="$STAGING_DIR/${APP_NAME}-${VERSION}.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

info "Submitting to Apple notary service…"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id  "$NOTARIZE_APPLE_ID" \
    --team-id   "$NOTARIZE_TEAM_ID" \
    --password  "$NOTARIZE_PASSWORD" \
    --wait \
    --output-format plist \
| tee "$STAGING_DIR/notarytool-result.plist"

STATUS=$(
    /usr/libexec/PlistBuddy -c "Print :status" "$STAGING_DIR/notarytool-result.plist" 2>/dev/null \
    || echo "unknown"
)
[[ "$STATUS" == "Accepted" ]] || error "Notarization failed (status: $STATUS). Check notarytool-result.plist."

info "Notarization accepted. Stapling ticket…"
xcrun stapler staple "$APP_BUNDLE"

# ── 6. Create DMG ─────────────────────────────────────────────────────────────

info "Creating DMG…"
mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

# Temporary uncompressed DMG
TMP_DMG="$STAGING_DIR/tmp.dmg"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -ov -format UDRW \
    "$TMP_DMG"

# Convert to read-only compressed DMG
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_PATH"

# Sign the DMG itself
codesign \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$DMG_PATH"

info "DMG created: $DMG_PATH"

# ── 7. Done ───────────────────────────────────────────────────────────────────

echo ""
echo "✓ Release complete: ${APP_NAME}-${VERSION}.dmg"
echo "  Path:    $DMG_PATH"
echo "  SHA256:  $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
