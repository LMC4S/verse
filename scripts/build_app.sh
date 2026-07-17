#!/bin/zsh
# Builds Verse.app into dist/.
#
# Uses swiftc directly because the Command Line Tools' SwiftPM is currently
# broken (missing BuildServerProtocol.framework). Once full Xcode is
# installed, `swift build -c release` works from Package.swift too.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/verse
swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos26.0 \
  Sources/Verse/*.swift \
  -o .build/verse/Verse

APP=dist/Verse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/verse/Verse "$APP/Contents/MacOS/Verse"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ -f build/icon.icns ]]; then
  cp build/icon.icns "$APP/Contents/Resources/icon.icns"
fi

codesign --force --sign - "$APP"
echo "✓ Built $APP"
