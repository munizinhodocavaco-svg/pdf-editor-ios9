"""Gera o wallpaper (.cpbitmap) e o thumbnail para o iPad 2 (iOS 9).

Formato do .cpbitmap (verificado no aparelho):
    <1024 x 1024 pixels RGBA, row-major, top-down>  (4.194.304 bytes)
    <bplist de 89 bytes com as propriedades do CGImage>

O bplist e reaproveitado do arquivo original (mesma largura/altura/colorspace),
apenas os pixels sao trocados.

Composicao (a foto entra DO JEITO QUE FOI ENVIADA):
    - A foto NAO e cortada: entra inteira na faixa visivel de 768x1024.
    - O fundo do canvas e a propria cor de fundo da foto, entao a tela fica
      100% preenchida de forma continua, sem faixas e sem tarjas.
    - Nenhuma cor, filtro, sombra ou distorcao e aplicada.
"""
import os
import sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Lucas Muniz\Downloads\PERFIL.png"
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

    # cor de fundo da propria foto (canto superior esquerdo)
    bg = src.getpixel((0, 0))

    # --- a foto inteira, cabendo na faixa visivel de 768x1024 ---
    scale = min(VISIBLE_W / src.width, SIZE / src.height)
    art_w = round(src.width * scale)
    art_h = round(src.height * scale)
    art = src.resize((art_w, art_h), Image.LANCZOS)

    # --- canvas 1024x1024 com a cor de fundo da foto ---
    canvas = Image.new("RGBA", (SIZE, SIZE), bg)

    # centralizado na area visivel (a faixa visivel e o centro de 768 px)
    x0 = (SIZE - VISIBLE_W) // 2
    art_x = x0 + (VISIBLE_W - art_w) // 2
    art_y = (SIZE - art_h) // 2
    canvas.alpha_composite(art, (art_x, art_y))

    # preview = exatamente o que aparece na tela (recorte central 768x1024)
    canvas.convert("RGB").crop((x0, 0, x0 + VISIBLE_W, SIZE)).save(OUT_PREVIEW)

    # ---- .cpbitmap ----
    px = canvas.convert("RGBA").tobytes()
    assert len(px) == SIZE * SIZE * 4, len(px)
    with open(OUT_CPBITMAP, "wb") as f:
        f.write(px)
        f.write(tail)

    # ---- thumbnail (116x154) a partir do recorte 3:4 ----
    crop = canvas.convert("RGB").crop((x0, 0, x0 + VISIBLE_W, SIZE))
    crop.resize(THUMB, Image.LANCZOS).save(OUT_THUMB, "JPEG", quality=92)

    print("fonte:", os.path.basename(SRC), src.size, "-> arte", art.size, "em", (art_x, art_y))
    print("fundo:", bg)
    print("cpbitmap:", os.path.getsize(OUT_CPBITMAP), "bytes")
    print("thumbnail:", os.path.getsize(OUT_THUMB), "bytes")
    print("preview:", OUT_PREVIEW)


if __name__ == "__main__":
    main()
