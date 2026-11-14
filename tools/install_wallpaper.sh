#!/bin/sh
# Instala o wallpaper (.cpbitmap) na TELA DE BLOQUEIO do iPad 2 (iOS 9).
#
# Roda NO APARELHO (via SSH). Precisa dos arquivos ja enviados:
#   /tmp/LockBackground.cpbitmap
#   /tmp/LockBackgroundThumbnail.jpg
#
# IMPORTANTE - tela inicial:
#   O SpringBoard guarda as variantes JA RENDERIZADAS do wallpaper em
#   /var/mobile/Library/Caches/com.apple.springboard.sharedimagecache/Wallpaper/
#   (arquivos shared-2020..., shared-2030..., etc). Se elas ficarem velhas, a
#   tela inicial mostra uma faixa com o wallpaper antigo por baixo da foto.
#   A solucao e apagar essas variantes: o SpringBoard as recria a partir do
#   LockBackground.cpbitmap (com o zoom/perspectiva corretos, do jeito do iOS).

SB=/var/mobile/Library/SpringBoard
W=/var/mobile/Library/Caches/com.apple.springboard.sharedimagecache/Wallpaper

if [ ! -f /tmp/LockBackground.cpbitmap ]; then
	echo "ERRO: /tmp/LockBackground.cpbitmap nao encontrado"
	exit 1
fi

# ---- tela de bloqueio ----
cp -f /tmp/LockBackground.cpbitmap "$SB/LockBackground.cpbitmap"
cp -f /tmp/LockBackgroundThumbnail.jpg "$SB/LockBackgroundThumbnail.jpg"
chown mobile:mobile "$SB/LockBackground.cpbitmap" "$SB/LockBackgroundThumbnail.jpg"
chmod 600 "$SB/LockBackground.cpbitmap"
chmod 644 "$SB/LockBackgroundThumbnail.jpg"

# ---- limpa as variantes em cache (tela inicial) ----
rm -f "$W"/shared-\(2020* 2>/dev/null
rm -f "$W"/shared-\(2030* 2>/dev/null
rm -f "$W"/shared-\(2070* 2>/dev/null
rm -f "$W"/shared-\(2071* 2>/dev/null

# ---- recarrega o SpringBoard para aplicar ----
killall SpringBoard 2>/dev/null
sleep 8
killall -9 SpringBoard 2>/dev/null
sleep 6

echo "OK - wallpaper aplicado na tela de bloqueio"
ls -la "$SB" | grep -i lockbackground
