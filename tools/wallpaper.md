# Wallpaper (proteção de tela) do iPad 2 via USB

Coloca uma imagem como **papel de parede da tela de bloqueio** do iPad 2 (iOS 9.3.5)
diretamente pelo USB, sem precisar abrir os Ajustes do iPad.

## Como o iOS 9 guarda o wallpaper

O SpringBoard guarda a tela de bloqueio em dois arquivos:

| Arquivo | Descrição |
|---|---|
| `/var/mobile/Library/SpringBoard/LockBackground.cpbitmap` | a imagem em si (1024×1024) |
| `/var/mobile/Library/SpringBoard/LockBackgroundThumbnail.jpg` | miniatura 116×154 usada no zoom da tela de bloqueio |

Formato do `.cpbitmap` (verificado no aparelho):

```
+-----------------------------------------------+  offset 0x000000
| 1024 x 1024 pixels  (4.194.304 bytes)        |  row-major, de cima para baixo
|   ordem dos canais: B G R A                   |  <-- ATENÇÃO (veja abaixo)
+-----------------------------------------------+  offset 0x400000
| bplist de 89 bytes com as propriedades do      |  kCGColorSpaceSRGB, 1024x1024
| CGImage (mesmo do arquivo original)            |
+-----------------------------------------------+  offset 0x400059
```

### ⚠️ Ordem dos canais: **BGRA**, não RGBA

O iOS 9 grava os pixels em ordem **Azul, Verde, Vermelho, Alpha**.
Se escrever em RGRA, a tela de bloqueio aparece com **vermelho e azul trocados**
(ex.: uma camisa amarela aparece ciano, tons de pele ficam azulados).

Isso foi confirmado decodificando o wallpaper original do iOS 9: lendo como RGRA
dá uma "flor amarela"; desfazendo a troca (BGRA) dá o wallpaper correto do
iOS 9 — azul/teal com laranja, idêntico ao `LockBackgroundThumbnail.jpg`.

### ⚠️ Tela 4:3

O iPad 2 tem tela 768×1024 (retrato). O SpringBoard recorta o canvas quadrado
de 1024×1024 pelo centro, mostrando só **768 px de largura**. Por isso a foto
é dimensionada para **cobrir 768×1024** (igual o recorte de papel de parede do
próprio iOS) e colocada nessa faixa central.

## Uso

```powershell
# 1) Gerar (recebe o caminho da foto; 2º argumento = quanto cortar do topo)
python tools\make_wallpaper_photo.py "C:\Users\...\foto.jpg" 0.0

# 2) Enviar
python _ipad2\sh.py --put "$env:TEMP\LockBackground_new.cpbitmap" /tmp/LockBackground.cpbitmap
python _ipad2\sh.py --put "$env:TEMP\LockBackgroundThumbnail_new.jpg" /tmp/LockBackgroundThumbnail.jpg

# 3) Instalar (só a tela de bloqueio) e recarregar o SpringBoard
python _ipad2\sh.py "cp /tmp/LockBackground.cpbitmap /var/mobile/Library/SpringBoard/; \
  cp /tmp/LockBackgroundThumbnail.jpg /var/mobile/Library/SpringBoard/; \
  chown mobile:mobile /var/mobile/Library/SpringBoard/LockBackground*; \
  chmod 600 /var/mobile/Library/SpringBoard/LockBackground.cpbitmap; \
  killall SpringBoard"
```

O wallpaper original fica salvo em
`/var/mobile/Library/SpringBoard/_backup_wallpaper/`.

## Desfazer

```powershell
python _ipad2\sh.py "cp /var/mobile/Library/SpringBoard/_backup_wallpaper/LockBackground.cpbitmap.orig \
  /var/mobile/Library/SpringBoard/LockBackground.cpbitmap; \
  chown mobile:mobile /var/mobile/Library/SpringBoard/LockBackground.cpbitmap; \
  killall SpringBoard"
```

## Observações

- Só a **tela de bloqueio** é alterada. A tela inicial usa outros arquivos
  (cache `com.apple.springboard.sharedimagecache/Wallpaper/`) e não é tocada.
- A imagem aparece quando a tela é bloqueada; um `killall SpringBoard`
  (ou reiniciar o iPad) já força a recarga.
- `tools/getcat.py` baixa arquivos via SSH (funciona com nomes que o SFTP
  do iOS 9 não consegue ler, como os do cache de wallpaper).
