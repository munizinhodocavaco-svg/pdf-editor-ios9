# PDF Editor para iPad 2 (iOS 9.3.5, armv7)

App de leitura e anotação de PDF, escrito em Objective-C, compilado com **Theos**
para **iOS 9.3 / ARMv7**. Roda em iPad 2, 3, 4 e iPad mini 1 com iOS 9 (jailbreak).

## Recursos

- **Lápis**: desenho livre sobre a página, com 5 cores.
- **Borracha**: apaga traços tocando neles.
- **Marcador de texto**: realce semitransparente.
- **Desfazer**: `NSUndoManager` nas anotações.
- **Salvamento automático**: as anotações ficam em `<pdf>.annotations.json`, ao lado do PDF, e são recarregadas ao reabrir o app.
- **Salvar PDF**: gera um PDF achatado (página + anotações) em Documentos.
- **Compartilhar**: envia o PDF anotado pela folha de compartilhamento.
- **5 tamanhos de página**: navegação Anterior/Próxima.

## Como compilar (GitHub Actions)

O workflow `.github/workflows/build-ios9.yml` roda em `ubuntu-22.04`:

1. Instala Theos + toolchain Linux.
2. Instala o SDK `iPhoneOS9.3.sdk` (theos/sdks).
3. Instala `ldid`.
4. Executa `theos/build.sh` (compila `armv7` e monta o `.ipa`).
5. Verifica o `.ipa` com `verify-ipa.py`.
6. Publica o artefato **PDFEditor-iOS9-armv7**.

Baixe o `.ipa` na aba **Actions** do repositório.

## Instalar no iPad 2 (jailbroken)

1. Conecte o iPad via USB.
2. **3uTools** (Windows): `Apps` → `Importar e Instalar` → escolha `PDFEditor.ipa`.
3. Alternativa (Linux/mac): `pymobiledevice3 apps install PDFEditor.ipa`.

## Usar o app

1. Copie arquivos PDF para a pasta **Documentos** do app (3uTools → Gerenciador de Arquivos,
   ou iTunes → Compartilhamento de Arquivos).
2. Abra o **PDF Editor**, toque em **Recarregar** e escolha o PDF.
3. Use **Lápis / Borracha / Marcador**, escolha a cor e desenhe com o dedo.
4. **Salvar PDF** grava `nome-anotado.pdf` em Documentos; **Compartilhar** abre a folha de envio.

## Estrutura

```
theos/
├── Makefile                  # TARGET iOS 9.3, ARCHS armv7
├── control                   # pacote .deb
├── build.sh                  # build + empacotamento .ipa
└── PDFEditor/
    ├── Info.plist
    ├── main.m / AppDelegate.m
    ├── DocumentListViewController.m
    ├── RootViewController.m
    ├── PDFPageView.m         # render CGPDFPage + toques
    ├── Annotation.m          # modelo + desenho em CGContext
    └── AnnotationStore.m     # persistência JSON por página
```

## Observações técnicas (iOS 9 / ARMv7)

- Renderização via `CGPDFPage` + `CGContextDrawPDFPage` (não há PDFKit no iOS 9).
- Coordenadas das anotações são normalizadas (0..1) — não quebram ao girar a tela.
- `self.view.bounds` é usado no layout (evita o cache de `TGScreenSize()`).
- Assinatura ad-hoc com `ldid`; instalação exige AppSync no dispositivo.
