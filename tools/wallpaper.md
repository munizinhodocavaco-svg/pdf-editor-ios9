# Wallpaper (proteção de tela) do iPad 2 via USB

Coloca uma imagem como **papel de parede da tela de bloqueio** do iPad 2 (iOS 9.3.5)
diretamente pelo USB, sem precisar abrir os Ajustes do iPad.

## Como o iOS 9 guarda o wallpaper

O SpringBoard guarda a tela de bloqueio em dois arquivos:

| Arquivo | Descrição |
|---|---|
| `/var/mobile/Library/SpringBoard/LockBackground.cpbitmap` | a imagem em si (1024×1024 RGBA cru) |
| `/var/mobile/Library/SpringBoard/LockBackgroundThumbnail.jpg` | miniatura 116×154 usada no zoom da tela de bloqueio |

Formato do `.cpbitmap` (verificado no aparelho):

```
+-----------------------------------------------+  offset 0x000000
| 1024 x 1024 pixels  RGBA  (4.194.304 bytes)  |  row-major, de cima para baixo
+-----------------------------------------------+  offset 0x400000
| bplist de 89 bytes com as propriedades do      |  kCGColorSpaceSRGB, 1024x1024
| CGImage (mesmo do arquivo original)            |
+-----------------------------------------------+  offset 0x400059
```

Como a largura/altura e o espaço de cor não mudam, o bplist do arquivo original
é reaproveitado e **só os pixels são trocados**.

> O iPad 2 tem tela 4:3 (768×1024). O SpringBoard recorta a imagem quadrada
> pelo centro, mostrando 768 px de largura. Por isso o script desenha o logo
> já com 768 px de largura no centro de um canvas 1024×1024.

## Uso

```powershell
# 1) Gerar os arquivos (precisa do Pillow)
python tools\make_wallpaper.py

# 2) Enviar para o iPad (via SSH/USB)
python _ipad2\sh.py --put "$env:TEMP\LockBackground_new.cpbitmap" /tmp/LockBackground.cpbitmap
python _ipad2\sh.py --put "$env:TEMP\LockBackgroundThumbnail_new.jpg" /tmp/LockBackgroundThumbnail.jpg

# 3) Instalar (com backup) e reiniciar o SpringBoard
python _ipad2\sh.py "cp /tmp/LockBackground.cpbitmap /var/mobile/Library/SpringBoard/; \
  cp /tmp/LockBackgroundThumbnail.jpg /var/mobile/Library/SpringBoard/; \
  chown mobile:mobile /var/mobile/Library/SpringBoard/LockBackground*; \
  chmod 600 /var/mobile/Library/SpringBoard/LockBackground.cpbitmap; \
  killall SpringBoard"
```

O backup do wallpaper original fica em
`/var/mobile/Library/SpringBoard/_backup_wallpaper/`.

## Desfazer

```powershell
python _ipad2\sh.py "cp /var/mobile/Library/SpringBoard/_backup_wallpaper/LockBackground.cpbitmap.orig \
  /var/mobile/Library/SpringBoard/LockBackground.cpbitmap; \
  chown mobile:mobile /var/mobile/Library/SpringBoard/LockBackground.cpbitmap; \
  killall SpringBoard"
```

## Observações

- A tela inicial (home) usa outro arquivo e **não** é alterada por este script.
- A imagem é aplicada quando a tela é bloqueada; um `killall SpringBoard`
  (ou reiniciar o iPad) já força a recarga.
