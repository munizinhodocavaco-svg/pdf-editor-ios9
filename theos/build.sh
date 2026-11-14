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

echo "=== Building RemoteAccess ==="
cd theos/RemoteAccess
make clean
make package FINAL=1
cd ../..

# Extract .app from .deb and create IPA for RemoteAccess
DEB_FILE_RA=$(ls theos/RemoteAccess/packages/com.lucas.remoteaccess_*_iphoneos-arm.deb 2>/dev/null | head -1)
if [ -n "$DEB_FILE_RA" ]; then
    echo "=== Creating IPA from .deb (RemoteAccess) ==="
    rm -rf theos/RemoteAccess/build/ipa
    mkdir -p theos/RemoteAccess/build/ipa/Payload
    dpkg-deb -x "$DEB_FILE_RA" theos/RemoteAccess/build/ipa
    if [ -d "theos/RemoteAccess/build/ipa/Applications/RemoteAccess.app" ]; then
        mv theos/RemoteAccess/build/ipa/Applications/RemoteAccess.app theos/RemoteAccess/build/ipa/Payload/
        cd theos/RemoteAccess/build/ipa
        zip -r ../../../../RemoteAccess.ipa Payload
        cd ../../../..
        echo "=== Generated: RemoteAccess.ipa ==="
        ls -la RemoteAccess.ipa
    else
        echo "ERROR: RemoteAccess.app not found in .deb"
    fi
else
    echo "ERROR: RemoteAccess .deb file not found"
fi

echo "=== Copying artifacts ==="
mkdir -p artifacts
cp theos/PDFEditor.ipa artifacts/PDFEditor.ipa 2>/dev/null || true
cp RemoteAccess.ipa artifacts/RemoteAccess.ipa 2>/dev/null || true
# ScreenMirror .deb is in theos/ScreenMirror/packages/
cp theos/ScreenMirror/packages/com.screenmirror_*_iphoneos-arm.deb artifacts/ScreenMirror.deb 2>/dev/null || true

echo "=== Done ==="
ls -la artifacts/
ls -la theos/PDFEditor.ipa 2>/dev/null || true
ls -la RemoteAccess.ipa 2>/dev/null || true