# FactuTPV Agent — one-liner installer for Windows.
#
# Uso (pegar en PowerShell como administrador):
#   iwr -useb https://raw.githubusercontent.com/ulisesbaena/factutpv-agent-releases/main/install.ps1 | iex
#
# Qué hace:
#   1. Descarga el .msi más reciente desde
#      github.com/ulisesbaena/factutpv-agent-releases/releases/latest
#   2. Lo ejecuta en modo "passive" (barra de progreso visible pero
#      sin diálogos) — el UAC pedirá permiso UNA sola vez
#   3. Abre el panel de administración en el navegador
#
# Seguridad: descarga siempre vía HTTPS contra el CDN de GitHub.
# El .msi todavía no está firmado con cert EV — Windows SmartScreen
# mostrará un aviso "Windows ha protegido tu PC" la primera vez.
# Botón "Más información" → "Ejecutar de todas formas". Este warning
# desaparecerá cuando tengamos el certificado de firma.
#
# Para DESINSTALAR (PowerShell admin):
#   iwr -useb https://raw.githubusercontent.com/ulisesbaena/factutpv-agent-releases/main/install.ps1 | iex; factutpv-uninstall

param(
    [string]$Action = "install"
)

$ErrorActionPreference = 'Stop'

$Repo = "ulisesbaena/factutpv-agent-releases"
$Base = if ($env:FACTUTPV_INSTALL_BASE) {
    $env:FACTUTPV_INSTALL_BASE
} else {
    "https://github.com/$Repo/releases/latest/download"
}

function Write-Info($msg) { Write-Host "▸ $msg" -ForegroundColor Cyan }
function Write-Good($msg) { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "! $msg" -ForegroundColor Yellow }
function Write-Die($msg)  { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

# Admin elevation check. MSI install genuinely needs admin — we
# verify up front so users don't get a confusing failure 30 s
# into the download.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Die @"
Este instalador necesita permisos de administrador para registrar
el servicio del sistema.

Cierra esta ventana, busca 'PowerShell' en el menú Inicio, haz
click derecho → 'Ejecutar como administrador', y vuelve a pegar
el comando.
"@
}

# --- Uninstall branch --------------------------------------------
if ($Action -eq "uninstall") {
    Write-Info "Desinstalando FactuTPV Agent..."

    $product = Get-WmiObject -Class Win32_Product -Filter "Name = 'FactuTPV Agent'" -ErrorAction SilentlyContinue
    if ($product) {
        $product.Uninstall() | Out-Null
        Write-Good "Desinstalado."
    } else {
        Write-Warn "FactuTPV Agent no estaba instalado (nada que hacer)."
    }
    exit 0
}

# --- Install branch ----------------------------------------------

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║             FactuTPV Agent — instalador                    ║"
Write-Host "║     https://factutpv.es · Soporte: soporte@factutpv.es     ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

Write-Info "Plataforma: Windows x64"

# --- Download ----------------------------------------------------
# Stable filename, no version — GitHub's `/releases/latest/download/`
# redirects to whichever tag is "latest" so one URL keeps working
# release after release.
$assetName = "factutpv-agent-windows-amd64.msi"
$url       = "$Base/$assetName"
$tmp       = Join-Path $env:TEMP "factutpv-agent-installer.msi"

Write-Info "Descargando $url..."
try {
    # UseBasicParsing keeps this working on PowerShell 5 (Windows
    # default) without needing IE COM — IE is deprecated and
    # optional on modern Windows.
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
} catch {
    Write-Die @"
No pude descargar $url
Verifica tu conexión a internet.
Si persiste, contacta: soporte@factutpv.es

Detalle: $($_.Exception.Message)
"@
}

Write-Good "Descarga completa ($([math]::Round((Get-Item $tmp).Length / 1MB, 2)) MB)"

# --- Install ----------------------------------------------------
Write-Info "Ejecutando instalador (el UAC pedirá permiso una vez)..."

# /passive: barra de progreso sin diálogos
# /norestart: no reiniciar el ordenador (no es necesario)
# /l*v "log.txt": log detallado en caso de fallo para soporte
$logFile = Join-Path $env:TEMP "factutpv-agent-install.log"
$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @(
    "/i", "`"$tmp`"",
    "/passive",
    "/norestart",
    "/l*v", "`"$logFile`""
) -Wait -PassThru -Verb RunAs

if ($proc.ExitCode -ne 0) {
    Write-Die @"
msiexec devolvió código $($proc.ExitCode). Log completo:
  $logFile

Envía ese archivo a soporte@factutpv.es para que te ayudemos.
"@
}

Write-Good "Instalado"
Write-Good "Servicio 'FactuTPVAgent' registrado, arrancando al boot"

# --- Open admin panel + final guidance --------------------------
Start-Sleep -Seconds 2
Write-Info "Abriendo panel de administración..."
try { Start-Process "http://127.0.0.1:17778/admin" } catch {}

Write-Host ""
Write-Good "FactuTPV Agent instalado correctamente."
Write-Host ""
Write-Host "  Panel de administración: http://127.0.0.1:17778/admin"
Write-Host "  Editar configuración:"
Write-Host "    notepad `"C:\ProgramData\FactuTPV Agent\config.json`""
Write-Host "    (necesitas abrir notepad como administrador)"
Write-Host "  Reiniciar el servicio:"
Write-Host "    Restart-Service FactuTPVAgent"
Write-Host "  Ver logs (Event Viewer):"
Write-Host "    eventvwr.msc → Windows Logs → Application → filter FactuTPVAgent"
Write-Host "  Desinstalar:"
Write-Host "    iwr -useb https://raw.githubusercontent.com/$Repo/main/install.ps1 | iex -Args uninstall"
Write-Host ""

# Clean up the installer MSI from temp — the installed service
# doesn't need it any more.
Remove-Item $tmp -ErrorAction SilentlyContinue
