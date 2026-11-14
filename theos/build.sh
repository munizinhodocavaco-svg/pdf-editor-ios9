#!/bin/bash
set -e

export THEOS="$HOME/theos"
export PATH="$THEOS/bin:$PATH"

echo "=== Building PDFEditor ==="
cd theos
make clean
make package FINAL=1

# Extract .app from .deb and create IPA
DEB_FILE=$(ls packages/com.lucaspdf.editor_*_iphoneos-arm.deb 2>/dev/null | head -1)
if [ -n "$DEB_FILE" ]; then
    echo "=== Creating IPA from .deb ==="
    rm -rf build/ipa
    mkdir -p build/ipa/Payload
    dpkg-deb -x "$DEB_FILE" build/ipa
    # The .app should be at build/ipa/Applications/PDFEditor.app
    if [ -d "build/ipa/Applications/PDFEditor.app" ]; then
        mv build/ipa/Applications/PDFEditor.app build/ipa/Payload/
        cd build/ipa
        zip -r ../../PDFEditor.ipa Payload
        cd ../..
        echo "=== Generated: theos/PDFEditor.ipa ==="
        ls -la PDFEditor.ipa
    else
        echo "ERROR: PDFEditor.app not found in .deb"
        exit 1
    fi
else
    echo "ERROR: .deb file not found"
    exit 1
fi
cd ..

echo "=== Building ScreenMirror ==="
cd theos/ScreenMirror
make clean
make package FINAL=1
cd ../..

echo "=== Copying artifacts ==="
mkdir -p artifacts
cp theos/PDFEditor.ipa artifacts/PDFEditor.ipa 2>/dev/null || true
cp theos/ScreenMirror_*_iphoneos-arm.deb artifacts/ScreenMirror.deb 2>/dev/null || true

echo "=== Done ==="
ls -la artifacts/
ls -la theos/PDFEditor.ipa 2>/dev/null || true