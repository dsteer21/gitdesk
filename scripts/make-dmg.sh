#!/bin/zsh
# Builds GitDesk.app and packages it as build/GitDesk-<version>.dmg for installing on other Macs.
# The DMG opens to the app beside an Applications shortcut: drag one onto the other to install.
set -euo pipefail

cd "${0:A:h}/.."
VERSION="${VERSION:-$(<VERSION)}"
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
# Unversioned copy for GitHub's /releases/latest/download/GitDesk.dmg link.
cp "$DMG" build/GitDesk.dmg
echo "✓ Built $DMG and build/GitDesk.dmg ($(du -h "$DMG" | cut -f1))"
