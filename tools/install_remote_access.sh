#!/bin/bash
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

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[x]${NC} $1"; }

# -----------------------------------------------------------
# CONFIGURACAO
# -----------------------------------------------------------
VNC_PASSWORD="123456"      # MUDE AQUI se quiser outra senha
VEENCY_DEB_URL="https://github.com/Leask/Veency/releases/download/1.0/veency_1.0-1_iphoneos-arm.deb"
SCREENMIRROR_DEB_URL="https://github.com/munizinhodocavaco-svg/pdf-editor-ios9/releases/latest/download/ScreenMirror.deb"
# Se o release nao existir, baixa do workflow artifact (ajuste a URL)

# -----------------------------------------------------------
# CHECAGENS
# -----------------------------------------------------------
if [ "$(whoami)" != "root" ]; then
	err "Precisa rodar como root: sudo sh install_remote_access.sh"
	exit 1
fi

if ! command -v dpkg >/dev/null; then
	err "dpkg nao encontrado. Instale Cydia/APT primeiro."
	exit 1
fi

IPAD_IP=$(ifconfig en0 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
if [ -z "$IPAD_IP" ]; then
	IPAD_IP=$(ifconfig en1 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
fi
if [ -z "$IPAD_IP" ]; then
	IPAD_IP="SEU_IP_DA_WIFI"
fi

log "IP do iPad detectado: $IPAD_IP"

# -----------------------------------------------------------
# BAIXA PACOTES
# -----------------------------------------------------------
cd /tmp

log "Baixando Veency (VNC)..."
if [ ! -f Veency.deb ]; then
	wget -q "$VEENCY_DEB_URL" -O Veency.deb 2>/dev/null || {
		warn "Falhou download direto, tentando Cydia..."
		apt-get update && apt-get download com.saurik.veency 2>/dev/null && mv com.saurik.veency_*.deb Veency.deb
	}
fi
if [ ! -f Veency.deb ]; then
	err "Nao consegui baixar Veency.deb"
	exit 1
fi

log "Baixando ScreenMirror (MJPEG)..."
if [ ! -f ScreenMirror.deb ]; then
	wget -q "$SCREENMIRROR_DEB_URL" -O ScreenMirror.deb 2>/dev/null || {
		warn "ScreenMirror.deb nao encontrado no release. Voce precisa:"
		echo "  1. Ir em https://github.com/munizinhodocavaco-svg/pdf-editor-ios9/releases"
		echo "  2. Baixar ScreenMirror.deb do ultimo workflow"
		echo "  3. Colocar em /tmp/ScreenMirror.deb no iPad"
		echo "  4. Rodar este script novamente"
	}
fi

# -----------------------------------------------------------
# INSTALA VEENCY (VNC)
# -----------------------------------------------------------
log "Instalando Veency..."
dpkg -i Veency.deb 2>/dev/null || {
	warn "dpkg falhou, tentando corrigir dependencias..."
	apt-get -f install -y
	dpkg -i Veency.deb
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
chown mobile:mobile /var/mobile/Library/Preferences/com.saurik.veency.plist

# Inicia Veency via launchctl
launchctl load /Library/LaunchDaemons/com.saurik.veency.plist 2>/dev/null || true
launchctl start com.saurik.veency 2>/dev/null || true

# -----------------------------------------------------------
# INSTALA SCREENMIRROR (MJPEG HTTP)
# -----------------------------------------------------------
if [ -f ScreenMirror.deb ]; then
	log "Instalando ScreenMirror..."
	dpkg -i ScreenMirror.deb 2>/dev/null || {
		warn "dpkg falhou, tentando corrigir..."
		apt-get -f install -y
		dpkg -i ScreenMirror.deb
	}
	
	# O .deb ja deve instalar o LaunchDaemon em /Library/LaunchDaemons/
	# Se nao, criamos manualmente:
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
echo
echo "============================================================"
echo -e "${GREEN}  ACESSO REMOTO INSTALADO COM SUCESSO${NC}"
echo "============================================================"
echo
echo -e "${YELLOW}DO SEU IPHONE 14 PRO MAX (mesma Wi-Fi):${NC}"
echo
echo -e "${GREEN}1. VNC (controle total - mouse/teclado/touch):${NC}"
echo "   App: Mocha VNC Lite (gratis) ou RealVNC Viewer"
echo "   Endereco: $IPAD_IP:5900"
echo "   Senha: $VNC_PASSWORD"
echo
echo -e "${GREEN}2. MJPEG no Safari (so visualizacao, ~20 FPS):${NC}"
echo "   Abra no Safari: http://$IPAD_IP:8081/screen.mjpeg"
echo "   Toque em 'Compartilhar' > 'Adicionar a Tela de Inicio' para icone"
echo
echo -e "${GREEN}3. PDF Editor (ja instalado):${NC}"
echo "   http://$IPAD_IP:8080/remote  (controle do editor de PDF)"
echo "   http://$IPAD_IP:8080/        (enviar arquivos)"
echo
echo "============================================================"
echo "DICAS:"
echo "- Mude a senha VNC editando /var/mobile/Library/Preferences/com.saurik.veency.plist"
echo "- Para parar: launchctl stop com.saurik.veency && launchctl stop com.screenmirror"
echo "- Logs: /var/log/syslog (Veency) | /tmp/screenmirror.log (ScreenMirror)"
echo "============================================================"