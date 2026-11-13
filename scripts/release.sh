#!/bin/zsh
# Publishes a GitHub release of the version in ./VERSION: ./scripts/release.sh
# Builds the DMG, tags the pushed HEAD as v<version> and uploads GitDesk-<version>.dmg plus GitDesk.dmg,
# so https://github.com/dsteer21/gitdesk/releases/latest/download/GitDesk.dmg always serves the newest build.
set -euo pipefail

cd "${0:A:h}/.."
VERSION="${1:-$(<VERSION)}"
TAG="v${VERSION}"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"

fail() { echo "✗ $1" >&2; exit 1; }

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "VERSION file must hold a version like 1.1.0"
[[ "$VERSION" == "$(<VERSION)" ]] || fail "$VERSION doesn't match the VERSION file ($(<VERSION)); update and commit it first"
"$GH" auth status >/dev/null 2>&1 || fail "Log in to GitHub first: gh auth login"

# The release must match code that is on GitHub, so refuse uncommitted or unpushed work.
[[ -z "$(git status --porcelain)" ]] || fail "Commit your changes first (working tree isn't clean)"
git fetch -q origin
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH" 2>/dev/null)" ]] || fail "Push $BRANCH first (HEAD doesn't match origin/$BRANCH)"
"$GH" release view "$TAG" >/dev/null 2>&1 && fail "Release $TAG already exists"

VERSION="$VERSION" ./scripts/make-dmg.sh

# Only publish builds Apple has notarised (stapled ticket on the DMG).
xcrun stapler validate -q "build/GitDesk-${VERSION}.dmg" || fail "The DMG isn't notarised; check the Developer ID certificate and notary profile"

NOTES="Download **GitDesk.dmg**, open it and drag GitDesk onto Applications. Needs macOS 14 or later and git.

Signed with a Developer ID and notarised by Apple, so it opens without any security warnings."

echo "→ Publishing $TAG…"
"$GH" release create "$TAG" "build/GitDesk-${VERSION}.dmg" build/GitDesk.dmg \
    --target "$(git rev-parse HEAD)" --title "GitDesk ${VERSION}" --notes "$NOTES" --generate-notes
echo "✓ Released $TAG"
echo "  Latest download: https://github.com/dsteer21/gitdesk/releases/latest/download/GitDesk.dmg"
