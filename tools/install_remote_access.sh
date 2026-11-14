#!/bin/sh
# ============================================================
# INSTALADOR ACESSO REMOTO IPAD 2 (iOS 9.3.5 JAILBREAK)
# Instala: Veency (VNC) + ScreenMirror (MJPEG no Safari)
# Rode NO IPAD via SSH como root
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo "${GREEN}[+]${NC} $1"; }
warn() { echo "${YELLOW}[!]${NC} $1"; }
err() { echo "${RED}[x]${NC} $1"; }

# -----------------------------------------------------------
# CONFIGURACAO
# -----------------------------------------------------------
VNC_PASSWORD="123456"

# URLs de download (fallback multiplos)
VEENCY_URLS="https://github.com/Leask/Veency/releases/download/1.0/veency_1.0-1_iphoneos-arm.deb https://cydia.saurik.com/api/share/com.saurik.veency/latest/deb"
SCREENMIRROR_URLS="https://github.com/munizinhodocavaco-svg/pdf-editor-ios9/releases/latest/download/ScreenMirror.deb https://github.com/munizinhodocavaco-svg/pdf-editor-ios9/releases/download/latest/ScreenMirror.deb"

# -----------------------------------------------------------
# CHECAGENS
# -----------------------------------------------------------
# Check if running as root (whoami/id may not exist)
if [ "$(pwd)" != "/private/var/root" ] && [ ! -w "/private/var/root" ]; then
    err "Precisa rodar como root. Rode: su -c 'sh /tmp/install_remote_access.sh'"
    exit 1
fi

if ! command -v dpkg >/dev/null 2>&1; then
    err "dpkg nao encontrado. Instale Cydia/APT primeiro."
    exit 1
fi

# Get IP using python if available, else try other methods
get_ip() {
    # Try python
    if command -v python >/dev/null 2>&1; then
        python -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8",80)); print(s.getsockname()[0])' 2>/dev/null && return
    fi
    # Try ifconfig
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig en0 2>/dev/null | grep 'inet ' | sed 's/.*inet \([0-9.]*\).*/\1/' | head -1 && return
    fi
    # Try ip
    if command -v ip >/dev/null 2>&1; then
        ip addr show en0 2>/dev/null | grep 'inet ' | sed 's/.*inet \([0-9.]*\)\/.*/\1/' | head -1 && return
    fi
    echo "SEU_IP_DA_WIFI"
}

IPAD_IP=$(get_ip)
log "IP do iPad detectado: $IPAD_IP"

# -----------------------------------------------------------
# FUNCAO: BAIXA COM FALLBACK
# -----------------------------------------------------------
download_with_fallback() {
    output="$1"
    shift
    urls="$1"
    
    for url in $urls; do
        log "Tentando: $url"
        if wget -q --timeout=30 "$url" -O "$output" 2>/dev/null; then
            if [ -s "$output" ]; then
                size=$(ls -l "$output" | sed 's/.* \([0-9]*\) .*/\1/')
                log "Baixado: $output (${size} bytes)"
                return 0
            fi
        fi
        warn "Falhou: $url"
    done
    return 1
}

# -----------------------------------------------------------
# BAIXA PACOTES
# -----------------------------------------------------------
cd /tmp

log "Baixando Veency (VNC)..."
if [ ! -f Veency.deb ] || [ ! -s Veency.deb ]; then
    download_with_fallback Veency.deb "$VEENCY_URLS" || {
        warn "Download direto falhou, tentando via APT (Cydia)..."
        apt-get update -qq 2>/dev/null && apt-get download com.saurik.veency 2>/dev/null && mv com.saurik.veency_*.deb Veency.deb 2>/dev/null
    }
fi
if [ ! -f Veency.deb ] || [ ! -s Veency.deb ]; then
    err "Nao consegui baixar Veency.deb"
    err "Baixe manualmente e coloque em /tmp/Veency.deb"
    exit 1
fi

log "Baixando ScreenMirror (MJPEG)..."
if [ ! -f ScreenMirror.deb ] || [ ! -s ScreenMirror.deb ]; then
    download_with_fallback ScreenMirror.deb "$SCREENMIRROR_URLS"
fi

# -----------------------------------------------------------
# INSTALA VEENCY (VNC)
# -----------------------------------------------------------
log "Instalando Veency..."
dpkg -i Veency.deb 2>/dev/null || {
    warn "dpkg falhou, tentando corrigir dependencias..."
    apt-get -f install -y 2>/dev/null
    dpkg -i Veency.deb 2>/dev/null || true
}

# Configura senha VNC
log "Configurando senha VNC: $VNC_PASSWORD"
mkdir -p /var/mobile/Library/Preferences
cat > /var/mobile/Library/Preferences/com.saurik.veency.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Password</key>
    <string>$VNC_PASSWORD</string>
    <key>ViewOnly</key>
    <false/>
</dict>
</plist>
EOF
chown mobile:mobile /var/mobile/Library/Preferences/com.saurik.veency.plist 2>/dev/null || true

# Inicia Veency via launchctl
launchctl load /Library/LaunchDaemons/com.saurik.veency.plist 2>/dev/null || true
launchctl start com.saurik.veency 2>/dev/null || true

# -----------------------------------------------------------
# INSTALA SCREENMIRROR (MJPEG HTTP)
# -----------------------------------------------------------
if [ -f ScreenMirror.deb ] && [ -s ScreenMirror.deb ]; then
    log "Instalando ScreenMirror..."
    dpkg -i ScreenMirror.deb 2>/dev/null || {
        warn "dpkg falhou, tentando corrigir..."
        apt-get -f install -y 2>/dev/null
        dpkg -i ScreenMirror.deb 2>/dev/null || true
    }
    
    if [ ! -f /Library/LaunchDaemons/com.screenmirror.plist ]; then
        log "Criando LaunchDaemon para ScreenMirror..."
        cat > /Library/LaunchDaemons/com.screenmirror.plist <<'LAUNCHEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.screenmirror</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ScreenMirror</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>mobile</string>
</dict>
</plist>
LAUNCHEOF
    fi
    
    launchctl load /Library/LaunchDaemons/com.screenmirror.plist 2>/dev/null || true
    launchctl start com.screenmirror 2>/dev/null || true
else
    warn "ScreenMirror.deb nao encontrado - pulando instalacao"
    warn "Voce pode compilar manualmente: cd theos/ScreenMirror && make package"
fi

# -----------------------------------------------------------
# REINICIA SPRINGBOARD (aplica tudo)
# -----------------------------------------------------------
log "Reiniciando SpringBoard..."
killall SpringBoard 2>/dev/null
sleep 5

# -----------------------------------------------------------
# RESULTADO
# -----------------------------------------------------------
echo ""
echo "============================================================"
echo "${GREEN}  ACESSO REMOTO INSTALADO COM SUCESSO${NC}"
echo "============================================================"
echo ""
echo "${YELLOW}DO SEU IPHONE 14 PRO MAX (mesma Wi-Fi):${NC}"
echo ""
echo "${GREEN}1. VNC (controle total - mouse/teclado/touch):${NC}"
echo "   App: Mocha VNC Lite (gratis) ou RealVNC Viewer"
echo "   Endereco: $IPAD_IP:5900"
echo "   Senha: $VNC_PASSWORD"
echo ""
echo "${GREEN}2. MJPEG no Safari (so visualizacao, ~20 FPS):${NC}"
echo "   Abra no Safari: http://$IPAD_IP:8081/screen.mjpeg"
echo "   Toque em 'Compartilhar' > 'Adicionar a Tela de Inicio' para icone"
echo ""
echo "${GREEN}3. PDF Editor (ja instalado):${NC}"
echo "   http://$IPAD_IP:8080/remote  (controle do editor de PDF)"
echo "   http://$IPAD_IP:8080/        (enviar arquivos)"
echo ""
echo "============================================================"
echo "DICAS:"
echo "- Mude a senha VNC editando /var/mobile/Library/Preferences/com.saurik.veency.plist"
echo "- Para parar: launchctl stop com.saurik.veency && launchctl stop com.screenmirror"
echo "- Logs: /var/log/syslog (Veency) | /tmp/screenmirror.log (ScreenMirror)"
echo "============================================================"