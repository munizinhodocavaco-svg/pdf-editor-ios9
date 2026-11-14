"""Gera o wallpaper (.cpbitmap) e o thumbnail para o iPad 2 (iOS 9).

Formato do .cpbitmap (verificado no dispositivo):
    <1024 x 1024 pixels RGBA, row-major, top-down>  (4.194.304 bytes)
    <bplist de 89 bytes com as propriedades do CGImage>

O bplist e reaproveitado do arquivo original (mesma largura/altura/colorspace),
apenas os pixels sao trocados.
"""
import os
import sys
from PIL import Image

SRC = r"C:\Users\Lucas Muniz\Downloads\PERFIL.png"
ORIG_CPBITMAP = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackground.cpbitmap"
OUT_CPBITMAP = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackground_new.cpbitmap"
OUT_THUMB = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackgroundThumbnail_new.jpg"
OUT_PREVIEW = r"C:\Users\Lucas Muniz\AppData\Local\Temp\wallpaper_preview.png"

SIZE = 1024          # lado do arquivo .cpbitmap
VISIBLE_W = 768      # largura realmente visivel na tela 4:3 do iPad 2
THUMB = (116, 154)  # tamanho do thumbnail existente


def main():
    original = open(ORIG_CPBITMAP, "rb").read()
    tail = original[0x400000:]
    assert len(tail) == 89, f"trailer inesperado: {len(tail)}"
    assert tail.startswith(b"bplist00"), "trailer nao e bplist"

    src = Image.open(SRC).convert("RGBA")
    bg = src.getpixel((0, 0))[:3]

    # Canvas 1024x1024 com o fundo original
    canvas = Image.new("RGBA", (SIZE, SIZE), bg + (255,))

    # O desenho (quadrado) cabe na largura visivel e fica centralizado verticalmente
    design = src.resize((VISIBLE_W, VISIBLE_W), Image.LANCZOS)
    off = (SIZE - VISIBLE_W) // 2
    canvas.alpha_composite(design, (off, off))

    # Preview do que o usuario vera (recorte central 768x1024 = 3:4)
    canvas.convert("RGB").crop((off, 0, off + VISIBLE_W, SIZE)).save(OUT_PREVIEW)

    # ---- .cpbitmap ----
    rgba = canvas.convert("RGBA")
    px = rgba.tobytes()
    assert len(px) == SIZE * SIZE * 4, len(px)
    with open(OUT_CPBITMAP, "wb") as f:
        f.write(px)
        f.write(tail)

    # ---- thumbnail (116x154) a partir do recorte 3:4 ----
    crop = canvas.convert("RGB").crop((off, 0, off + VISIBLE_W, SIZE))
    thumb = crop.resize(THUMB, Image.LANCZOS)
    thumb.save(OUT_THUMB, "JPEG", quality=90)

    print("cpbitmap:", os.path.getsize(OUT_CPBITMAP), "bytes")
    print("thumbnail:", os.path.getsize(OUT_THUMB), "bytes")
    print("preview:", OUT_PREVIEW)


if __name__ == "__main__":
    main()
