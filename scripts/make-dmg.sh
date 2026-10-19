#!/usr/bin/env bash
# Build Vermut.app and wrap it in a UDZO disk image with an Applications symlink.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v hdiutil >/dev/null 2>&1; then
    echo "error: scripts/make-dmg.sh must run on macOS (needs hdiutil)." >&2
    exit 1
fi

"$ROOT/build.sh"

APP="$ROOT/Vermut.app"
if [[ ! -d "$APP" ]]; then
    echo "error: Vermut.app was not produced by ./build.sh" >&2
    exit 1
fi

VERSION="1.0.0"
if [[ -f "$ROOT/VERSION" ]]; then
    VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
fi
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/vermut-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

cp -R "$APP" "$STAGE/Vermut.app"
ln -s /Applications "$STAGE/Applications"

OUT="$ROOT/Vermut-${VERSION}.dmg"
rm -f "$OUT"

hdiutil create \
    -volname "Vermut" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$OUT"

echo "Created $OUT"
echo "Unsigned build. Gatekeeper will warn until the app is notarized."
echo "Users can right-click → Open, or:"
echo "  xattr -dr com.apple.quarantine /Applications/Vermut.app"
