#!/bin/bash
# Compiles the Apple Speech helpers into src/bin/.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p src/bin
for name in apple_transcribe apple_stream; do
  out="src/bin/verse-${name//_/-}"
  swiftc -O \
    -framework Speech -framework AVFoundation \
    -o "$out" \
    "src/${name}.swift"
  codesign --force --sign - "$out"
  echo "Built $out"
done
