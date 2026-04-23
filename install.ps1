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

# --- Make sure the service is actually running ------------------
#
# The WiX manifest ships with Start="install" so msiexec triggers
# StartService and Wait="yes" blocks until SCM reports RUNNING.
# In theory the service is up by the time we reach this point.
# In practice some combinations (older Windows Installer, slow
# disks, AV scanning the new EXE, a previous failed install
# leaving the service Disabled) fall off that happy path. Belt-
# and-braces: check Get-Service, attempt Start-Service if needed,
# and poll /healthz until it answers before opening the browser.
$svc = Get-Service -Name "FactuTPVAgent" -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Die @"
El servicio 'FactuTPVAgent' no quedó registrado por el MSI. Revisa
el log en $logFile y contacta soporte@factutpv.es.
"@
}

# Configure recovery: auto-restart the service if it crashes for ANY
# reason (unpair from the admin panel, panic, OOM, …). Without this,
# an unpair left the service in Stopped state because OnUnpair calls
# os.Exit(0) expecting the supervisor to relaunch — launchd/systemd
# do that by default; Windows SCM does not unless failure actions are
# configured. Seen live on the pilot Windows 11 host: unpairing the
# agent killed the service and the local admin panel went 503.
#
# "reset= 60" — failure counter resets after 60s without incident.
# "actions= restart/5000/…" — restart after 5s on first, second and
#                             subsequent failures. SCM stops after 3
#                             attempts unless another 60s-free window
#                             passes, which protects against a crash-
#                             loop saturating CPU.
Write-Info "Configurando recovery del servicio (auto-restart en crashes)..."
& sc.exe failure FactuTPVAgent reset= 60 actions= restart/5000/restart/5000/restart/5000 | Out-Null

if ($svc.Status -ne "Running") {
    Write-Info "Arrancando servicio FactuTPVAgent..."
    try {
        Start-Service -Name "FactuTPVAgent" -ErrorAction Stop
    } catch {
        Write-Die @"
No pude arrancar el servicio FactuTPVAgent.
Revisa Event Viewer → Windows Logs → Application → filter FactuTPVAgent
para ver el motivo exacto y contacta soporte@factutpv.es.

Detalle: $($_.Exception.Message)
"@
    }
}

# Wait for /healthz to answer. The service reports RUNNING to the
# SCM BEFORE it finishes binding to :17777 (binding happens on a
# goroutine after svc.Run returns), so a bare Get-Service check
# isn't enough. 15 s is generous — on a normal machine the HTTP
# server is up in <1 s; on a slow laptop or under heavy AV scanning
# it can take 3-5 s. If the deadline fires we still open the
# browser page because it'll auto-retry on the "refresh" button
# once the service catches up.
Write-Info "Esperando a que el panel responda..."
$deadline = (Get-Date).AddSeconds(15)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:17777/healthz" `
            -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 400 }
}
if ($ready) {
    Write-Good "Servicio 'FactuTPVAgent' arrancado (panel responde en :17777)"
} else {
    Write-Warn "El servicio está registrado pero el panel aún no responde."
    Write-Warn "Abriremos el navegador — si sale 'conexión rechazada', espera 5 s y pulsa Recargar."
}

# --- Open admin panel + final guidance --------------------------
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
