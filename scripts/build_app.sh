#!/bin/zsh
# Builds Verse.app into dist/.
#
# Uses swiftc directly because the Command Line Tools' SwiftPM is currently
# broken (missing BuildServerProtocol.framework). Once full Xcode is
# installed, `swift build -c release` works from Package.swift too.
set -euo pipefail
cd "$(dirname "$0")/.."

# Pin to the Command Line Tools: the machine's active developer dir may point
# at an Xcode whose license isn't accepted yet, which bricks every dev tool.
export DEVELOPER_DIR=/Library/Developer/CommandLineTools

mkdir -p .build/verse
swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macos26.0 \
  Sources/Verse/*.swift \
  -o .build/verse/Verse

APP="dist/Verse Dev.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/verse/Verse "$APP/Contents/MacOS/Verse"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ -f build/icon.icns ]]; then
  cp build/icon.icns "$APP/Contents/Resources/icon.icns"
fi
cp Support/local_mlx_transcribe.py "$APP/Contents/Resources/"
cp Resources/*.png "$APP/Contents/Resources/"

codesign --force --sign - "$APP"
echo "✓ Built $APP"
