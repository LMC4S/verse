#!/bin/bash
# Compiles the Apple Speech helper into src/bin/verse-apple-transcribe.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p src/bin
swiftc -O \
  -framework Speech -framework AVFoundation \
  -o src/bin/verse-apple-transcribe \
  src/apple_transcribe.swift
codesign --force --sign - src/bin/verse-apple-transcribe
echo "Built src/bin/verse-apple-transcribe"
