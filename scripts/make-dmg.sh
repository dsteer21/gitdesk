#!/bin/zsh
# Builds GitDesk.app and packages it as build/GitDesk-<version>.dmg for installing on other Macs.
# The DMG opens to the app beside an Applications shortcut: drag one onto the other to install.
# With a Developer ID certificate and the "gitdesk-notary" keychain profile, the DMG is signed,
# notarised by Apple and stapled, so it opens on any Mac without a Gatekeeper warning.
set -euo pipefail

cd "${0:A:h}/.."
VERSION="${VERSION:-$(<VERSION)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-gitdesk-notary}"   # created once with: xcrun notarytool store-credentials
DMG="build/GitDesk-${VERSION}.dmg"
STAGING="build/dmg"

VERSION="$VERSION" ./scripts/build-app.sh

echo "→ Packaging $DMG…"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/GitDesk.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Compressed, read-only image.
hdiutil create -volname "GitDesk ${VERSION}" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "→ Notarising with Apple (usually a few minutes)…"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        # Confirm Gatekeeper accepts it as a downloaded, notarised DMG.
        spctl --assess --type open --context context:primary-signature -v "$DMG"
    else
        echo "! Signed but NOT notarised: no \"$NOTARY_PROFILE\" keychain profile" >&2
    fi
fi
# Unversioned copy for GitHub's /releases/latest/download/GitDesk.dmg link.
cp "$DMG" build/GitDesk.dmg
echo "✓ Built $DMG and build/GitDesk.dmg ($(du -h "$DMG" | cut -f1))"
