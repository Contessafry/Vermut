#!/bin/bash
set -e

echo "Building Vermut for macOS..."

if ! command -v swift &> /dev/null; then
    echo "Error: Swift is not installed or not in PATH"
    echo "Please install Xcode or Xcode Command Line Tools"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="1.0.0"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
fi

echo "Running tests..."
swift test

echo "Building release binary..."
swift build -c release --arch arm64

BUILD_DIR="$SCRIPT_DIR/.build/arm64-apple-macosx/release"
APP_NAME="Vermut"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Vermut</string>
    <key>CFBundleDisplayName</key>
    <string>Vermut</string>
    <key>CFBundleIdentifier</key>
    <string>com.opensource.vermut</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Vermut</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Vermut Contributors. Open Source Software.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.games</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>exe</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Windows Executable</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>msi</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Windows Installer</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>bat</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Windows Batch File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
EOF

ICONSET="$SCRIPT_DIR/Resources/AppIcon.iconset"
ICNS_DEST="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
if command -v iconutil >/dev/null 2>&1 && [ -d "$ICONSET" ]; then
    echo "Building AppIcon.icns from Resources/AppIcon.iconset (light-background primary)…"
    iconutil -c icns "$ICONSET" -o "$ICNS_DEST"
elif [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$ICNS_DEST"
elif [ -f "$SCRIPT_DIR/icon.icns" ]; then
    cp "$SCRIPT_DIR/icon.icns" "$ICNS_DEST"
else
    echo "Note: iconutil not found; AppIcon.icns will be generated on macOS builds."
fi

# Copied PNG/PDF glyphs. Asset-catalog SVGs are not compiled by actool in this
# SwiftPM path, so the app loads these files from Bundle.main Resources.
BRAND_SRC="$SCRIPT_DIR/Sources/CaskLauncherCore/BrandAssets"
if [ ! -d "$BRAND_SRC" ]; then
    BRAND_SRC="$SCRIPT_DIR/Resources/BrandAssets"
fi
if [ ! -d "$BRAND_SRC" ]; then
    echo "Error: BrandAssets directory missing (expected Sources/CaskLauncherCore/BrandAssets)"
    exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/Resources/BrandAssets"
cp -R "$BRAND_SRC/." "$APP_BUNDLE/Contents/Resources/BrandAssets/"

copy_spm_bundle() {
    local name="$1"
    local found
    found=$(find "$BUILD_DIR" -maxdepth 3 -name "$name" | head -n 1)
    if [ -n "$found" ]; then
        cp -R "$found" "$APP_BUNDLE/Contents/Resources/"
        # Bundle.module for a wrapped executable also looks next to Contents/MacOS/
        cp -R "$found" "$APP_BUNDLE/Contents/MacOS/"
    fi
}
copy_spm_bundle "CaskLauncherApp_CaskLauncherApp.bundle"
copy_spm_bundle "CaskLauncherCore_CaskLauncherCore.bundle"

REQUIRED_BRAND=(
    steam.png steam@2x.png steam@3x.png steam.pdf
    epic.png epic@2x.png epic@3x.png epic.pdf
    gog.png gog@2x.png gog@3x.png gog.pdf
    vermut-mark.png vermut-mark@2x.png vermut-mark@3x.png
    vermut-wordmark.png vermut-wordmark@2x.png vermut-wordmark@3x.png vermut-wordmark.pdf
    vermut-wordmark-white.png vermut-wordmark-white@2x.png vermut-wordmark-white@3x.png vermut-wordmark-white.pdf
)
missing=0
for f in "${REQUIRED_BRAND[@]}"; do
    if [ ! -s "$APP_BUNDLE/Contents/Resources/BrandAssets/$f" ]; then
        echo "Error: missing or empty $f in Vermut.app/Contents/Resources/BrandAssets"
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "Brand asset verification failed."
    exit 1
fi
echo "Brand assets verified in $APP_BUNDLE/Contents/Resources/BrandAssets"

echo ""
echo "✅ Build complete!"
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run the app:"
echo "  open $APP_BUNDLE"
echo ""
echo "To install system-wide:"
echo "  cp -r $APP_BUNDLE /Applications/"
