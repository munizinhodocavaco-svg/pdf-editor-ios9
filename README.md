# Leitor / Editor Pdf LM — iPad 2 (iOS 9.3.5, armv7)

App em Objective-C compilado com **Theos** para **iOS 9.3 / ARMv7**, feito para
iPad 2 (jailbreak). Lê PDFs, permite desenhar com o dedo e salvar o resultado.

## Recursos

- **Lápis (✏️)**: desenho livre sobre a página, traço suave com pontas arredondadas.
- **Borracha (🧽)**: apaga **arrastando** o dedo sobre os traços (sem cursor na tela).
- **Marcador (🖍️)**: realce semitransparente que cobre a linha de texto (blend *Multiply*).
- **Tamanhos 1x / 2x / 3x**: cada ferramenta (lápis, borracha, marcador) tem 3 espessuras proporcionais.
- **Cores**: botões **Preto / Branco / Vermelho** + botão arco-íris para abrir o seletor de espectro (matiz × saturação/brilho).
- **Modo Eco**: liga/desliga a economia de energia (brilho da tela em 35% + redesenho a 30 FPS).
- **Desfazer**: pilha própria de desfazer (até 300 ações) — corrige crash do NSUndoManager no iOS 9.
- **Salvamento automático**: as anotações ficam em `<pdf>.annotations.json`, ao lado do PDF.
- **Salvar PDF**: gera um PDF achatado em Documentos — ou substitui o original.
- **Compartilhar**: envia o PDF anotado pela folha de compartilhamento.
- **Excluir PDF**: deslize para a esquerda na lista.
- **Importar por rede**:
  - **Navegador**: servidor HTTP embutido; envie PDFs de qualquer computador na mesma rede Wi-Fi.
  - **WebDAV**: monte a pasta do app como unidade de rede no Windows (`net use Z: http://IP:8080/`).
  - **Link direto**: baixe um PDF a partir de uma URL da rede local.

## Interface

- **Barra de ferramentas (topo)**: ✏️ Lápis / 🧽 Borracha / 🖍️ Marcador | 1x / 2x / 3x
- **Cores**: Preto / Branco / Vermelho + botão arco-íris (seletor HSV) + botão **Eco**
- **Barra inferior (rodapé)**: Anterior / Página X de Y / Próxima
- **Lista de documentos**: puxar para recarregar, botão **Importar** abre a tela de rede.

## Economia de bateria (importante no iPad 2)

O iPad 2 tem bateria de 2011, então o app foi feito para pesar pouco:

- **Servidor web lazy**: não sobe junto com o app. Ele só liga quando você abre a
  tela **Importar** e desliga sozinho quando você sai (se você ligou manualmente
  com o botão, ele continua). Fica com o socket fechado o resto do tempo, então
  o rádio Wi-Fi do iPad fica ocioso.
- **Servidor desligado ao sair do app**: sai para a tela de bloqueio ou troca de
  app → o servidor para.
- **Botão Eco**: na tela do editor, toque em **Eco** para:
  - reduzir o brilho da tela para 35% (o brilho original do sistema é devolvido
    assim que você desliga o Eco ou sai do app),
  - limitar o redesenho do traço a 30 FPS (os pontos do toque continuam sendo
    gravados todos, só o desenho é adiado).
- **Gravação agrupada**: as anotações são salvas 1,5 s após a última alteração
  (antes era uma gravação de arquivo por traço). Ao sair da tela do editor ou do
  app, a gravação é feita na hora — nada se perde.

## Importar arquivos (jeito mais fácil)

1. Conecte o iPad e o computador na mesma rede Wi-Fi.
2. Abra o **Leitor / Editor Pdf LM** e toque em **Importar** (canto superior esquerdo).
3. O app mostra um endereço, por exemplo `http://192.168.0.12:8080`.
4. No computador, abra esse endereço no navegador e envie os PDFs.
5. Os arquivos aparecem na lista na hora. Toque em **Recarregar** se necessário.

No Windows também é possível abrir o endereço no **Explorador de Arquivos** ou
mapear como unidade:

```
net use Z: http://192.168.0.12:8080/
```

O servidor só funciona enquanto a tela **Importar** estiver aberta (e o app em
primeiro plano) — isso economiza bateria. Se quiser deixá-lo ligado o tempo
todo, toque em **Iniciar servidor** na própria tela.

### Alternativa por USB

3uTools → `Apps` → `Gerenciador de Arquivos` → pasta **Documentos** do Leitor / Editor Pdf LM.

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
│   ├── Info.plist               # nome Leitor / Editor Pdf LM, ícones, ATS
│   ├── Icon-*.png / Logo.png    # ícones e logo
└── PDFEditor/
    ├── main.m / AppDelegate.m
    ├── DocumentListViewController.m
    ├── NetworkViewController.m  # tela Importar (Wi-Fi / link)
    ├── WebServer.m              # servidor HTTP + WebDAV embutido
    ├── RootViewController.m     # editor: ferramentas, tamanhos, cores, espectro
    ├── ColorPickerViewController.m  # seletor de cor com espectro HSV
    ├── PDFPageView.m            # render CGPDFPage + toques + cache
    ├── Annotation.m             # modelo + desenho em CGContext
    ├── AnnotationStore.m        # persistência JSON por página (async)
    └── Log.m                    # log de diagnóstico
```

## Observações técnicas (iOS 9 / ARMv7)

- Renderização via `CGPDFPage` + `CGContextDrawPDFPage` (não há PDFKit no iOS 9).
- Coordenadas das anotações são normalizadas (0..1) — não quebram ao girar a tela.
- O app é assinado com `ldid -S entitlements.plist`; a instalação exige AppSync Unified.
- **Cache de desempenho**: a página PDF + anotações já desenhadas ficam em `CGImage`; durante um traço novo apenas ele é redesenhado (custo constante). Usa `coalescedTouchesForTouch` para traços suaves sem quadros extras.
- Gravação de anotações em fila serial (`dispatch_queue`) para nao travar a UI.
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
- **Lentidão ao desenhar**: esta versão usa cache de imagem composta e redesenho
  apenas da área do traço ativo. Em iPad 2 (256 MB RAM) o ganho é significativo.