# FactuTPV Agent — one-liner installer for Windows.
#
# Uso (pegar en PowerShell como administrador):
#   iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1 | iex
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
# Para DESINSTALAR (PowerShell admin), descarga el script y ejecútalo
# con -Action uninstall (Invoke-Expression NO acepta parámetros, así
# que la variante con pipe no funciona — hay que guardar a archivo):
#
#   $u = "https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1"
#   $s = Join-Path $env:TEMP "factutpv-installer.ps1"
#   Invoke-WebRequest -Uri $u -OutFile $s -UseBasicParsing
#   & $s -Action uninstall
#
# También puedes desinstalar desde "Aplicaciones instaladas" de Windows
# (Configuración → Aplicaciones → buscar "FactuTPV Agent" → Desinstalar).

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

    # Step 1: stop the service BEFORE uninstalling the MSI. If the
    # service is in a bad state (CouldNotStartService loop from a
    # broken binary) `Stop-Service` may throw — ignore and proceed,
    # the MSI will bulldoze it regardless via ServiceControl Remove.
    try {
        $svc = Get-Service -Name "FactuTPVAgent" -ErrorAction Stop
        if ($svc.Status -ne "Stopped") {
            Write-Info "Parando servicio FactuTPVAgent..."
            Stop-Service -Name "FactuTPVAgent" -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warn "Servicio FactuTPVAgent no está registrado (sigo)."
    }

    # Step 2: prefer the CIM-backed Win32_Product query (modern
    # Win10+ systems). Falls back to the WMI class for legacy.
    # Both queries are SLOW on Windows (~30 s total) because they
    # walk every MSI on the machine to match by name — expected.
    Write-Info "Localizando MSI instalado (puede tardar ~30 s)..."
    $product = $null
    try {
        $product = Get-CimInstance -ClassName Win32_Product -Filter "Name = 'FactuTPV Agent'" -ErrorAction SilentlyContinue
    } catch {
        $product = Get-WmiObject -Class Win32_Product -Filter "Name = 'FactuTPV Agent'" -ErrorAction SilentlyContinue
    }

    if ($product) {
        # Step 3: let the MSI do its job. This removes the binary,
        # the service registration, and the config (but NOT the data
        # directory at ProgramData, which keeps the paired JWT).
        Write-Info "Ejecutando uninstall del MSI ProductCode=$($product.IdentifyingNumber)..."
        $uninstallLog = Join-Path $env:TEMP "factutpv-agent-uninstall.log"
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @(
            "/x", $product.IdentifyingNumber,
            "/passive", "/norestart",
            "/l*v", "`"$uninstallLog`""
        ) -Wait -PassThru -Verb RunAs
        if ($proc.ExitCode -eq 0) {
            Write-Good "Desinstalado."
        } else {
            Write-Warn "msiexec devolvió código $($proc.ExitCode). Log: $uninstallLog"
            Write-Warn "Puedes probar la limpieza manual descrita al final."
        }
    } else {
        Write-Warn "No se encontró la entrada MSI 'FactuTPV Agent'."
        Write-Warn "Si hay restos sueltos (servicio registrado, carpeta en Program Files)"
        Write-Warn "usa la limpieza manual:"
        Write-Host "    sc.exe stop FactuTPVAgent"
        Write-Host "    sc.exe delete FactuTPVAgent"
        Write-Host "    Remove-Item 'C:\Program Files\FactuTPV Agent' -Recurse -Force"
    }

    # The JWT / keyring / queue stay in ProgramData so a re-install
    # pairs back automatically. If the operator wants a clean slate:
    Write-Host ""
    Write-Info "Datos del agente conservados en 'C:\ProgramData\FactuTPV Agent'."
    Write-Info "Para borrarlos también (perderás el pairing, tendrás que re-vincular):"
    Write-Host "    Remove-Item 'C:\ProgramData\FactuTPV Agent' -Recurse -Force"
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
try { Start-Process "http://127.0.0.1:17777/admin" } catch {}

Write-Host ""
Write-Good "FactuTPV Agent instalado correctamente."
Write-Host ""
Write-Host "  Panel de administración: http://127.0.0.1:17777/admin"
Write-Host "  Editar configuración:"
Write-Host "    notepad `"C:\ProgramData\FactuTPV Agent\config.json`""
Write-Host "    (necesitas abrir notepad como administrador)"
Write-Host "  Reiniciar el servicio:"
Write-Host "    Restart-Service FactuTPVAgent"
Write-Host "  Ver logs (Event Viewer):"
Write-Host "    eventvwr.msc → Windows Logs → Application → filter FactuTPVAgent"
Write-Host "  Desinstalar (3 pasos — iex no acepta parámetros):"
Write-Host "    `$u = 'https://cdn.jsdelivr.net/gh/$Repo@main/install.ps1'"
Write-Host "    `$s = Join-Path `$env:TEMP 'factutpv-installer.ps1'; Invoke-WebRequest -Uri `$u -OutFile `$s -UseBasicParsing"
Write-Host "    & `$s -Action uninstall"
Write-Host "  (alternativa: Configuración → Aplicaciones → FactuTPV Agent → Desinstalar)"
Write-Host ""

# Clean up the installer MSI from temp — the installed service
# doesn't need it any more.
Remove-Item $tmp -ErrorAction SilentlyContinue
