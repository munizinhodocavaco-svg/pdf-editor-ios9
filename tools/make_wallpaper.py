"""Gera o wallpaper (.cpbitmap) e o thumbnail para o iPad 2 (iOS 9).

Formato do .cpbitmap (verificado no aparelho):
    <1024 x 1024 pixels RGBA, row-major, top-down>  (4.194.304 bytes)
    <bplist de 89 bytes com as propriedades do CGImage>

O bplist e reaproveitado do arquivo original (mesma largura/altura/colorspace),
apenas os pixels sao trocados.

Composicao (tela do iPad 2 = 768x1024, 4:3 retrato):
    O SpringBoard recorta a imagem quadrada pelo centro, mostrando 768 px de
    largura. Entao o canvas 1024x1024 e preenchido com um fundo gradiente e a
    arte e colocada INTEIRA (sem corte) na faixa central visivel de 768x1024.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SRC = r"C:\Users\Lucas Muniz\Downloads\LOGO LM 22.png"
ORIG_CPBITMAP = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackground.cpbitmap"
OUT_CPBITMAP = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackground_new.cpbitmap"
OUT_THUMB = r"C:\Users\Lucas Muniz\AppData\Local\Temp\LockBackgroundThumbnail_new.jpg"
OUT_PREVIEW = r"C:\Users\Lucas Muniz\AppData\Local\Temp\wallpaper_preview.png"

SIZE = 1024          # lado do arquivo .cpbitmap
VISIBLE_W = 768      # largura realmente visivel na tela 4:3 do iPad 2
THUMB = (116, 154)  # tamanho do thumbnail existente

# Cores da identidade (teal -> verde) usadas no fundo
TEAL = (67, 159, 183)
GREEN = (56, 202, 121)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def make_background(w, h):
    """Fundo com gradiente diagonal suave + brilho radial no centro."""
    base = Image.new("RGB", (w, h), (255, 255, 255))
    px = base.load()
    # gradiente diagonal: teal no topo-esquerda -> verde embaixo-direita
    step = max(w, h) // 2
    for y in range(h):
        for x in range(0, w, 4):
            t = (x / w * 0.45 + y / h * 0.55)
            c = lerp(TEAL, GREEN, t)
            # mistura suave com o branco (8% a 17%) para o fundo preencher a tela toda
            k = 0.08 + 0.09 * t
            cc = tuple(int(round(255 + (c[i] - 255) * k)) for i in range(3))
            for k2 in range(4):
                if x + k2 < w:
                    px[x + k2, y] = cc

    # brilho radial suave (luz) atras da arte
    glow = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(glow)
    r = int(w * 0.55)
    d.ellipse([w // 2 - r, h // 2 - r, w // 2 + r, h // 2 + r], fill=40)
    glow = glow.filter(ImageFilter.GaussianBlur(r // 3))
    light = Image.new("RGB", (w, h), (255, 255, 255))
    base = Image.composite(light, base, glow)
    return base


def main():
    original = open(ORIG_CPBITMAP, "rb").read()
    tail = original[0x400000:]
    assert len(tail) == 89, f"trailer inesperado: {len(tail)}"
    assert tail.startswith(b"bplist00"), "trailer nao e bplist"

    logo = Image.open(SRC).convert("RGBA")

    # --- fundo do canvas inteiro (1024x1024) ---
    canvas = make_background(SIZE, SIZE).convert("RGBA")

    # --- arte: cabe inteira na faixa visivel, tocando as laterais ---
    art_w = VISIBLE_W
    art_h = round(logo.height * art_w / logo.width)
    art = logo.resize((art_w, art_h), Image.LANCZOS)

    # sombra bem suave, seguindo a silhueta da arte, para dar profundidade
    alpha = art.getchannel("A")
    shadow = Image.new("RGBA", (art_w + 80, art_h + 80), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", art.size, (31, 58, 70, 55)), (40, 40), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))

    # posicao: centralizada na area visivel (768 de largura no canvas de 1024)
    x0 = (SIZE - VISIBLE_W) // 2          # = 128
    art_x = x0
    art_y = (SIZE - art_h) // 2           # centralizado verticalmente

    canvas.alpha_composite(shadow, (art_x - 40, art_y - 40))
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

    print("arte dentro da tela visivel:", art.size, "em", (art_x, art_y))
    print("cpbitmap:", os.path.getsize(OUT_CPBITMAP), "bytes")
    print("thumbnail:", os.path.getsize(OUT_THUMB), "bytes")
    print("preview:", OUT_PREVIEW)


if __name__ == "__main__":
    main()
