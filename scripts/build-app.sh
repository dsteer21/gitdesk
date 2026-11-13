#!/bin/zsh
# Builds GitDesk.app into ./build. Pass --install to copy it into /Applications.
set -euo pipefail

cd "${0:A:h}/.."
APP="build/GitDesk.app"
# The version lives in ./VERSION; VERSION=x.y.z in the environment overrides it.
VERSION="${VERSION:-$(<VERSION)}"

# Universal binary (Apple Silicon + Intel) so the app runs on any Mac with macOS 14+.
ARCHS=(--arch arm64 --arch x86_64)

echo "→ Compiling (release, universal)…"
swift build -c release "${ARCHS[@]}"

echo "→ Bundling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
cp "$BIN_DIR/GitDesk" "$APP/Contents/MacOS/GitDesk"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GitDesk</string>
    <key>CFBundleDisplayName</key><string>GitDesk</string>
    <key>CFBundleIdentifier</key><string>uk.co.llexeter.gitdesk</string>
    <key>CFBundleExecutable</key><string>GitDesk</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with the Developer ID certificate when it's in the keychain (needed for notarisation:
# hardened runtime + secure timestamp). Without one, fall back to an ad-hoc signature,
# which is fine for local use. SIGN_IDENTITY overrides the automatic choice.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    echo "✓ Built $APP (signed: $SIGN_IDENTITY)"
else
    codesign --force --sign - "$APP"
    echo "✓ Built $APP (ad-hoc signed; no Developer ID certificate found)"
fi

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/GitDesk.app
    cp -R "$APP" /Applications/
    echo "✓ Installed to /Applications/GitDesk.app"
fi
