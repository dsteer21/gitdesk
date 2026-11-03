#!/bin/zsh
# Publishes a GitHub release: ./scripts/release.sh 1.1.0
# Builds the DMG, tags the pushed HEAD as v<version> and uploads GitDesk-<version>.dmg plus GitDesk.dmg,
# so https://github.com/dsteer21/gitdesk/releases/latest/download/GitDesk.dmg always serves the newest build.
set -euo pipefail

cd "${0:A:h}/.."
VERSION="${1:-}"
TAG="v${VERSION}"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"

fail() { echo "✗ $1" >&2; exit 1; }

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "Usage: ./scripts/release.sh <version>, e.g. 1.1.0"
"$GH" auth status >/dev/null 2>&1 || fail "Log in to GitHub first: gh auth login"

# The release must match code that is on GitHub, so refuse uncommitted or unpushed work.
[[ -z "$(git status --porcelain)" ]] || fail "Commit your changes first (working tree isn't clean)"
git fetch -q origin
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCH" 2>/dev/null)" ]] || fail "Push $BRANCH first (HEAD doesn't match origin/$BRANCH)"
"$GH" release view "$TAG" >/dev/null 2>&1 && fail "Release $TAG already exists"

VERSION="$VERSION" ./scripts/make-dmg.sh

NOTES="Download **GitDesk.dmg**, open it and drag GitDesk onto Applications. Needs macOS 14 or later and git.

The app isn't notarised, so on first launch open **System Settings → Privacy & Security** and click **Open Anyway** (or run \`xattr -dr com.apple.quarantine /Applications/GitDesk.app\`)."

echo "→ Publishing $TAG…"
"$GH" release create "$TAG" "build/GitDesk-${VERSION}.dmg" build/GitDesk.dmg \
    --target "$(git rev-parse HEAD)" --title "GitDesk ${VERSION}" --notes "$NOTES" --generate-notes
echo "✓ Released $TAG"
echo "  Latest download: https://github.com/dsteer21/gitdesk/releases/latest/download/GitDesk.dmg"
