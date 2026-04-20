#!/usr/bin/env bash
# FactuTPV Agent — one-liner installer for macOS and Linux.
#
# Uso (pegar en Terminal):
#   curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash
#
# Qué hace, paso por paso:
#
#   1. Detecta OS (Darwin/Linux) y arquitectura (arm64/amd64).
#   2. Descarga el instalador de la última release desde
#      https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest
#      (URL pública, sin necesidad de cuenta GitHub).
#   3. En macOS: limpia el atributo `com.apple.quarantine` que
#      macOS pone a cualquier fichero descargado — sin esto
#      Gatekeeper muestra "Apple no puede comprobar que no
#      contenga malware" antes de dejarte abrir el .pkg.
#   4. Instala con sudo usando la herramienta nativa de cada
#      plataforma (installer / apt / dnf / zypper). Pide tu
#      contraseña una sola vez.
#   5. Abre el panel de administración (http://127.0.0.1:17777/admin)
#      en tu navegador. Ahí ves el código de 6 dígitos para
#      vincular el agente con tu cuenta FactuTPV.
#
# Seguridad en tránsito: la descarga va siempre por HTTPS con
# el cert de github.com. Un MITM tendría que romper TLS del CDN
# de GitHub — a ese nivel cualquier otra actualización de macOS
# o Windows también estaría comprometida.
#
# Para DESINSTALAR:
#   curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash -s -- uninstall

set -euo pipefail

REPO="ulisesbaena/factutpv-agent-releases"
BASE="https://github.com/$REPO/releases/latest/download"

# Overridable via env var for testing against a pinned version:
#   FACTUTPV_INSTALL_BASE=https://github.com/$REPO/releases/download/v0.2.0 bash install.sh
BASE="${FACTUTPV_INSTALL_BASE:-$BASE}"

# Colour helpers. isatty() check so piping to a log file doesn't
# litter the output with escape codes.
if [ -t 1 ]; then
  BLUE='\033[0;34m' GREEN='\033[0;32m' RED='\033[0;31m' YELLOW='\033[0;33m' NC='\033[0m'
else
  BLUE='' GREEN='' RED='' YELLOW='' NC=''
fi

info()  { printf "${BLUE}▸${NC} %s\n" "$*"; }
good()  { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$*"; }
die()   { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

# ----------------------------------------------------------------
# Uninstall mode
# ----------------------------------------------------------------
if [ "${1:-}" = "uninstall" ]; then
  case "$(uname -s)" in
    Darwin)
      info "Desinstalando FactuTPV Agent en macOS..."
      sudo launchctl unload -w /Library/LaunchDaemons/com.factutpv.agent.plist 2>/dev/null || true
      sudo rm -f /Library/LaunchDaemons/com.factutpv.agent.plist
      sudo rm -f /usr/local/bin/factutpv-agent
      sudo rm -rf "/Library/Application Support/FactuTPV Agent"
      sudo rm -rf /var/log/factutpv-agent
      good "Desinstalado. Si quieres borrar la cola offline: rm -rf ~/Library/Caches/factutpv-agent"
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get remove --purge -y factutpv-agent
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf remove -y factutpv-agent
      elif command -v yum >/dev/null 2>&1; then
        sudo yum remove -y factutpv-agent
      elif command -v zypper >/dev/null 2>&1; then
        sudo zypper remove -y factutpv-agent
      else
        die "Gestor de paquetes no detectado. Desinstala manualmente."
      fi
      good "Desinstalado."
      ;;
    *) die "Sistema no soportado para uninstall: $(uname -s)" ;;
  esac
  exit 0
fi

# ----------------------------------------------------------------
# Normal install
# ----------------------------------------------------------------

echo "╔════════════════════════════════════════════════════════════╗"
echo "║             FactuTPV Agent — instalador                    ║"
echo "║     https://factutpv.es · Soporte: soporte@factutpv.es     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

# --- OS + arch detection -----------------------------------------
case "$(uname -s)" in
  Darwin) OS=darwin ; OS_LABEL="macOS" ;;
  Linux)  OS=linux  ; OS_LABEL="Linux" ;;
  *)      die "Sistema no soportado: $(uname -s). Para Windows ejecuta en PowerShell (como admin):
        iwr -useb https://cdn.jsdelivr.net/gh/$REPO@main/install.ps1 | iex" ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=amd64 ;;
  *)             die "Arquitectura no soportada: $(uname -m). Contacta soporte si necesitas este target." ;;
esac

info "Plataforma detectada: $OS_LABEL $ARCH"

# --- Package format -----------------------------------------------
if [ "$OS" = "darwin" ]; then
  EXT=pkg
elif command -v dpkg >/dev/null 2>&1; then
  EXT=deb
elif command -v rpm >/dev/null 2>&1; then
  EXT=rpm
else
  die "No detecté apt/dpkg ni rpm. ¿Qué distro usas? Contacta soporte."
fi
info "Formato de instalador: .$EXT"

# --- Build asset URL ---------------------------------------------
# GitHub's `/releases/latest/download/FILENAME` URL always
# redirects to whichever release is tagged as "latest". No API
# call needed; works on any repo (public in this case) without
# authentication. Assets use stable names (no version in the
# filename) so this URL keeps working release after release.
if [ "$OS" = "darwin" ]; then
  ASSET="factutpv-agent-darwin-$ARCH.pkg"
else
  ASSET="factutpv-agent-linux-$ARCH.$EXT"
fi
DL_URL="$BASE/$ASSET"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The downloaded file MUST keep its extension ($EXT = pkg | deb | rpm)
# for the native installer to accept it. macOS's `installer -pkg <path>`
# in particular rejects any path that doesn't end in ".pkg" with
# "the package path specified was invalid", even if the file bytes
# are a perfectly valid xar archive — it's a filename-suffix check,
# not a content check. Same defensive habit on Linux so dpkg/apt/rpm
# don't surprise us on minimal distros that validate extensions.
PKG_FILE="$TMP/factutpv-agent.$EXT"

# --- Download ----------------------------------------------------
info "Descargando $ASSET..."
if ! curl -fL --progress-bar "$DL_URL" -o "$PKG_FILE"; then
    die "No pude descargar $DL_URL
   Verifica tu conexión a internet.
   Si persiste, contacta: soporte@factutpv.es"
fi

# --- Platform-specific install path ------------------------------
case "$OS" in
  darwin)
    info "Limpiando quarantine flag (evita el warning de Gatekeeper)..."
    xattr -d com.apple.quarantine "$PKG_FILE" 2>/dev/null || true

    info "Instalando — pedirá tu contraseña de administrador..."
    sudo installer -pkg "$PKG_FILE" -target / || die "installer falló"

    good "Instalado en /usr/local/bin/factutpv-agent"
    good "Servicio com.factutpv.agent registrado en launchd"
    sleep 2
    info "Abriendo panel de administración en el navegador..."
    open "http://127.0.0.1:17777/admin" 2>/dev/null || true
    ;;

  linux)
    # We prefer `apt install ./file.deb` (Debian/Ubuntu) over
    # `dpkg -i` because apt resolves dependencies automatically;
    # dpkg alone fails if systemd pkg isn't present (rare but
    # possible on minimal installs).
    if [ "$EXT" = "deb" ]; then
      info "Instalando con apt..."
      sudo apt-get update -qq
      sudo apt-get install -y "$PKG_FILE"
    else
      info "Instalando con rpm..."
      sudo rpm -Uvh --force "$PKG_FILE" 2>/dev/null || \
        sudo dnf install -y "$PKG_FILE" 2>/dev/null || \
        sudo zypper install -y --allow-unsigned-rpm "$PKG_FILE" || \
        die "Ningún gestor (rpm/dnf/zypper) aceptó el paquete"
    fi
    good "Servicio factutpv-agent.service registrado en systemd"
    sudo systemctl enable --now factutpv-agent.service 2>/dev/null || true

    # Try to open admin panel in browser if there's a GUI session.
    if [ -n "${DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
      (sleep 2 && xdg-open "http://127.0.0.1:17777/admin") &
    fi
    ;;
esac

# --- Final guidance ----------------------------------------------
echo
good "FactuTPV Agent instalado correctamente."
echo
echo "  Panel de administración: http://127.0.0.1:17777/admin"
echo "  Editar configuración:"
case "$OS" in
  darwin) echo "    sudo nano /Library/Application\\ Support/FactuTPV\\ Agent/config.json" ;;
  linux)  echo "    sudo -g factutpv nano /etc/factutpv-agent/config.json" ;;
esac
echo "  Reiniciar el servicio:"
case "$OS" in
  darwin) echo "    sudo launchctl kickstart -k system/com.factutpv.agent" ;;
  linux)  echo "    sudo systemctl restart factutpv-agent" ;;
esac
echo "  Ver logs en vivo:"
case "$OS" in
  darwin) echo "    tail -f /var/log/factutpv-agent/stdout.log" ;;
  linux)  echo "    sudo journalctl -u factutpv-agent -f" ;;
esac
echo "  Desinstalar:"
echo "    curl -sSL https://cdn.jsdelivr.net/gh/$REPO@main/install.sh | bash -s -- uninstall"
echo
