"""Gera o wallpaper (.cpbitmap) da TELA DE BLOQUEIO do iPad 2 (iOS 9).

Formato do .cpbitmap (verificado no aparelho):
    <1024 x 1024 pixels, row-major, top-down>            (4.194.304 bytes)
    <bplist de 89 bytes com as propriedades do CGImage>

ATENCAO - ORDEM DOS CANAIS:
    O iOS 9 grava os pixels em ordem **BGRA** (Azul, Verde, Vermelho, Alpha).
    Escrever RGRA faz a tela de bloqueio aparecer com **vermelho e azul
    trocados** (ex.: camisa amarela vira ciano). Foi confirmado comparando
    o wallpaper original do iOS 9 (azul/laranja) com a leitura errada.

Composicao:
    A tela do iPad 2 tem 768x1024 (4:3 retrato). O SpringBoard recorta o
    canvas quadrado de 1024x1024 pelo centro, mostrando 768 px de largura.
"""
import os
import sys
from PIL import Image

ORIG_CPBITMAP = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackground.cpbitmap"
OUT_CPBITMAP = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackground_new.cpbitmap"
OUT_THUMB = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackgroundThumbnail_new.jpg"
OUT_PREVIEW = r"C:\Users\Lucas Muniz\AppData\Local\Temp\wallpaper_preview.png"

SIZE = 1024          # lado do arquivo .cpbitmap
VISIBLE_W = 768      # largura visivel na tela 4:3 do iPad 2
VISIBLE_H = 1024
THUMB = (116, 154)


def to_bgra_bytes(rgb_image):
    """RGB -> bytes no layout BGRA usado pelo iOS 9."""
    r, g, b = rgb_image.split()
    return Image.merge("RGBA", (b, g, r, Image.new("L", rgb_image.size, 255))).tobytes()


def cover(img, w, h, bias=0.0):
    scale = max(w / img.width, h / img.height)
    nw, nh = round(img.width * scale), round(img.height * scale)
    img = img.resize((nw, nh), Image.LANCZOS)
    left = (nw - w) // 2
    top = round((nh - h) * bias)
    return img.crop((left, top, left + w, top + h))


def main():
    src_path = sys.argv[1]
    bias = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0

    original = open(ORIG_CPBITMAP, "rb").read()
    tail = original[0x400000:]
    assert len(tail) == 89 and tail.startswith(b"bplist00"), "trailer inesperado"

    src = Image.open(src_path).convert("RGB")
    art = cover(src, VISIBLE_W, VISIBLE_H, bias)

    side = (SIZE - VISIBLE_W) // 2
    canvas = Image.new("RGB", (SIZE, SIZE))
    canvas.paste(art, (side, 0))
    canvas.paste(art.crop((0, 0, 2, VISIBLE_H)).resize((side, VISIBLE_H)), (0, 0))
    canvas.paste(art.crop((VISIBLE_W - 2, 0, VISIBLE_W, VISIBLE_H))
                 .resize((side, VISIBLE_H)), (side + VISIBLE_W, 0))

    visible = canvas.crop((side, 0, side + VISIBLE_W, SIZE))
    visible.save(OUT_PREVIEW)

    px = to_bgra_bytes(canvas)
    assert len(px) == SIZE * SIZE * 4
    with open(OUT_CPBITMAP, "wb") as f:
        f.write(px)
        f.write(tail)

    visible.resize(THUMB, Image.LANCZOS).save(OUT_THUMB, "JPEG", quality=92)
    print("fonte:", os.path.basename(src_path), src.size)
    print("canais: BGRA (corrigido)")
    print("cpbitmap:", os.path.getsize(OUT_CPBITMAP), "bytes")


if __name__ == "__main__":
    main()
