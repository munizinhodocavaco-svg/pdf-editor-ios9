#!/bin/bash
set -e

export THEOS="$HOME/theos"
export PATH="$THEOS/bin:$PATH"

echo "=== Building PDFEditor ==="
cd theos/PDFEditor
make clean
make package FINAL=1
cd ../..

echo "=== Building ScreenMirror ==="
cd theos/ScreenMirror
make clean
make package FINAL=1
cd ../..

echo "=== Copying artifacts ==="
mkdir -p artifacts
cp theos/PDFEditor.ipa artifacts/ 2>/dev/null || true
cp theos/ScreenMirror_*_iphoneos-arm.deb artifacts/ScreenMirror.deb 2>/dev/null || true

echo "=== Done ==="
ls -la artifacts/