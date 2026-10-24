#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DESTINATION="$PWD/build/AirSlide.app"
mkdir -p "$PWD/build"
STAGING=$(mktemp -d "$PWD/build/airslide-build.XXXXXX")
cleanup() {
    if [ ! -d "$DESTINATION" ] && [ -d "$STAGING/previous.app" ]; then
        mv "$STAGING/previous.app" "$DESTINATION"
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
APP="$STAGING/AirSlide.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -parse-as-library -target arm64-apple-macos14.0 macos/*.swift -o "$APP/Contents/MacOS/AirSlide" -framework SwiftUI -framework CoreMotion -framework SceneKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.tarabcak.airslide</string>
<key>CFBundleName</key><string>AirSlide</string>
<key>CFBundleExecutable</key><string>AirSlide</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSMotionUsageDescription</key><string>AirSlide uses AirPods motion to change presentation slides when you swing your wrist.</string>
</dict></plist>
PLIST
mkdir -p "$APP/Contents/Resources"
cp macos/Assets/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
# Never overwrite a mapped executable: macOS may terminate the old process
# when its signed code pages change. Publish only the finished signed bundle.
if [ -d "$DESTINATION" ]; then
    mv "$DESTINATION" "$STAGING/previous.app"
fi
mv "$APP" "$DESTINATION"
echo "$DESTINATION"
