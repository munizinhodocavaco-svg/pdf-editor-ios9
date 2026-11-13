# PDF LM — leitor e editor de PDF para iPad 2 (iOS 9.3.5, armv7)

App em Objective-C compilado com **Theos** para **iOS 9.3 / ARMv7**, feito para
iPad 2 (jailbreak). Lê PDFs, permite desenhar com o dedo e salvar o resultado.

## Recursos

- **Lápis**: desenho livre sobre a página, com 5 cores.
- **Borracha**: apaga traços tocando neles.
- **Marcador de texto**: realce semitransparente.
- **Desfazer**: `NSUndoManager` nas anotações.
- **Salvamento automático**: as anotações ficam em `<pdf>.annotations.json`, ao lado do PDF.
- **Salvar PDF**: gera um PDF achatado em Documentos.
- **Compartilhar**: envia o PDF anotado pela folha de compartilhamento.
- **Importar por rede** (novo):
  - **Navegador**: servidor HTTP embutido; envie PDFs de qualquer computador na mesma rede Wi-Fi.
  - **WebDAV**: monte a pasta do app como unidade de rede no Windows (`net use Z: http://IP:8080/`).
  - **Link direto**: baixe um PDF a partir de uma URL da rede local.

## Importar arquivos (jeito mais fácil)

1. Conecte o iPad e o computador na mesma rede Wi-Fi.
2. Abra o **PDF LM** e toque em **Importar** (canto superior esquerdo).
3. O app mostra um endereço, por exemplo `http://192.168.0.12:8080`.
4. No computador, abra esse endereço no navegador e envie os PDFs.
5. Os arquivos aparecem na lista na hora. Toque em **Recarregar** se necessário.

No Windows também é possível abrir o endereço no **Explorador de Arquivos** ou
mapear como unidade:

```
net use Z: http://192.168.0.12:8080/
```

O servidor só funciona enquanto o app está aberto em primeiro plano.

### Alternativa por USB

3uTools → `Apps` → `Gerenciador de Arquivos` → pasta **Documentos** do PDF LM.

## Como compilar (GitHub Actions)

O workflow `.github/workflows/build-ios9.yml` roda em `ubuntu-22.04`:

1. Instala Theos + toolchain Linux.
2. Instala o SDK `iPhoneOS9.3.sdk` (theos/sdks) e o stub `liblaunch.tbd` que falta nele.
3. Instala `ldid`.
4. Executa `theos/build.sh` (compila `armv7`, assina ad-hoc com `entitlements.plist` e monta o `.ipa`).
5. Verifica o `.ipa` com `verify-ipa.py`.
6. Publica o artefato **PDFEditor-iOS9-armv7**.

Baixe o `.ipa` na aba **Actions** do repositório.

## Instalar no iPad 2 (jailbroken)

1. Conecte o iPad via USB.
2. **3uTools** (Windows): `Apps` → `Importar e Instalar` → escolha `PDFEditor.ipa`.
3. Alternativa: `pymobiledevice3 apps install PDFEditor.ipa` (precisa de AppSync Unified).

## Estrutura

```
theos/
├── Makefile                     # TARGET iOS 9.3, ARCHS armv7, entitlements
├── control                      # pacote .deb
├── build.sh                     # build + empacotamento .ipa
├── entitlements.plist           # application-identifier etc. (assinatura ad-hoc)
├── Resources/
│   ├── Info.plist               # nome PDF LM, ícones, ATS
│   ├── Icon-*.png / Logo.png    # ícones e logo
└── PDFEditor/
    ├── main.m / AppDelegate.m
    ├── DocumentListViewController.m
    ├── NetworkViewController.m  # tela Importar (Wi-Fi / link)
    ├── WebServer.m              # servidor HTTP + WebDAV embutido
    ├── RootViewController.m
    ├── PDFPageView.m            # render CGPDFPage + toques
    ├── Annotation.m             # modelo + desenho em CGContext
    ├── AnnotationStore.m        # persistência JSON por página
    └── Log.m                    # log de diagnóstico
```

## Observações técnicas (iOS 9 / ARMv7)

- Renderização via `CGPDFPage` + `CGContextDrawPDFPage` (não há PDFKit no iOS 9).
- Coordenadas das anotações são normalizadas (0..1) — não quebram ao girar a tela.
- O app é assinado com `ldid -S entitlements.plist`; a instalação exige AppSync Unified.
- Diagnóstico de inicialização: o arquivo `/tmp/pdfeditor.log` é gravado antes de
  qualquer acesso ao sandbox (e `Documents/launch.log` quando o sandbox permite).
  Se `/tmp/pdfeditor.log` existir, o binário executou; se não existir, o launchd
  barrou o processo antes do `main`.

## Solução de problemas

- **App fecha ao abrir**: confira se o AppSync Unified está instalado e reinstale o IPA.
  O log em `/tmp/pdfeditor.log` mostra até onde a inicialização chegou.
- **Servidor não abre**: verifique se o iPad está no mesmo Wi-Fi e se a porta 8080
  não está bloqueada na rede.
- **PDF não aparece**: toque em **Recarregar**; só arquivos `.pdf` são listados.
