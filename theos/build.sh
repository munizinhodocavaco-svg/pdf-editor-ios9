#!/usr/bin/env bash
# Compila o PDF Editor para iOS 9.3 / ARMv7 e gera PDFEditor.ipa
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${THEOS:-}" ]; then
	export THEOS="$HOME/theos"
fi
export PATH="$THEOS/bin:$PATH"

echo "==> THEOS=$THEOS"
echo "==> Limpando build anterior"
make clean >/dev/null 2>&1 || true
rm -rf packages .theos PDFEditor.ipa build

echo "==> Compilando (armv7 / iOS 9.3)"
make package FINALPACKAGE=1

DEB=$(ls packages/*.deb | head -n1)
echo "==> Pacote: $DEB"

echo "==> Extraindo .app do .deb"
mkdir -p build/deb
dpkg-deb -x "$DEB" build/deb

APP=$(find build/deb -maxdepth 4 -name "*.app" -type d | head -n1)
if [ -z "$APP" ]; then
	echo "ERRO: .app nao encontrado dentro do .deb"
	exit 1
fi
echo "==> App: $APP"

mkdir -p build/Payload
cp -R "$APP" build/Payload/
cp -R "$APP" build/PDFEditor.app

echo "==> Empacotando IPA"
(cd build && zip -qry "../PDFEditor.ipa" Payload)
rm -rf build

echo "==> Gerado: $(pwd)/PDFEditor.ipa"
ls -l PDFEditor.ipa
