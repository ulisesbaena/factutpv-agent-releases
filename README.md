# FactuTPV Agent — downloads

Cross-platform print-bridge daemon for the [FactuTPV](https://factutpv.es)
point-of-sale. This repository hosts **only the distribution artefacts**:
binaries, installers, and install scripts. The source code lives in a
separate private repository.

---

## Instalación en un comando

### 🍎 macOS

Abre **Terminal** (⌘-Space → "Terminal") y pega:

```bash
curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash
```

El script detectará si tu Mac es Apple Silicon (M1/M2/M3/M4) o Intel,
descargará el `.pkg` adecuado, lo instalará y abrirá el panel de
administración en el navegador. **Pedirá tu contraseña una vez**
(para instalar el servicio del sistema).

Antes de pedir la contraseña, compara automáticamente el SHA-256 del
paquete con el `SHA256SUMS` de la release y aborta ante cualquier
diferencia. Esta comprobación detecta corrupción o una mezcla accidental
de releases; no autentica por sí sola al publicador.

> Si ves una advertencia de macOS "Apple no puede comprobar...", el
> script la sortea automáticamente. Puedes verificar el binario tú
> mismo con los checksums SHA-256 en `releases.json` de cada release.

### 🪟 Windows 10 / 11

Abre **PowerShell como administrador** (click derecho → "Ejecutar como
administrador") y pega:

```powershell
iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1 | iex
```

El UAC pedirá permiso una vez. El servicio `FactuTPVAgent` arrancará
al instante y después en cada arranque del ordenador.

El MSI se verifica contra `SHA256SUMS` antes de ejecutar `msiexec`. Es una
comprobación de integridad y coherencia de release, no una firma de código.

> La primera vez Windows SmartScreen puede mostrar "Windows ha protegido
> tu PC" → click en **Más información** → **Ejecutar de todas formas**.
> Esto desaparecerá cuando firmemos los instaladores con un
> certificado EV (próxima release mayor).

### 🐧 Linux (Debian/Ubuntu/Fedora/openSUSE)

```bash
curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash
```

Detecta automáticamente `apt` / `dnf` / `zypper` y usa el paquete
adecuado. Registra `factutpv-agent.service` en systemd.

---

## 🧪 Instalación **STAGING** (solo para testers)

Si estás probando cambios nuevos antes de que salgan a producción, usa
una **prerelease** pinchada a un tag concreto. Las prereleases apuntan a
`api-stg.factutpv.es` por defecto, se emparejan con el stg del backend,
y **no** interfieren con los clientes de producción (los one-liners de
arriba siempre sirven el último release estable gracias a que GitHub
omite las prereleases en la redirección `/releases/latest/`).

El tag concreto cambia con cada ronda de testing — mira en la [página
de releases](https://github.com/ulisesbaena/factutpv-agent-releases/releases)
cuál es la prerelease más reciente (las marcadas con `Pre-release`, tipo
`v1.1.0-stg.4`) y sustitúyelo en los comandos de abajo:

**macOS / Linux** (Terminal):

```bash
FACTUTPV_INSTALL_BASE="https://github.com/ulisesbaena/factutpv-agent-releases/releases/download/v1.1.0-stg.4" \
  curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash
```

**Windows** (PowerShell como administrador):

```powershell
$env:FACTUTPV_INSTALL_BASE="https://github.com/ulisesbaena/factutpv-agent-releases/releases/download/v1.1.0-stg.4"
iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1 | iex
```

Tras instalar, abre `http://localhost:17777/admin`: verás un cartel
visible "STAGING BUILD" dentro del `config.json` + el código de 6
dígitos que emparejarás contra **stg.factutpv.es → Ajustes →
Agentes → Vincular**.

> ⚠️ No mezcles builds stg con clientes de producción. El agente stg
> se comunica solo con `api-stg.factutpv.es`; intentar emparejarlo
> contra `factutpv.es` no funcionará.

Para volver al release de producción desde una instalación stg:

```bash
# macOS / Linux — desinstala + re-instala el one-liner normal
curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash -s -- uninstall
curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash
```

```powershell
# Windows
iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1 | iex -Args uninstall
iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1 | iex
```

---

## Instalación manual (sin one-liner)

Si prefieres descargar el instalador tú mismo, ve a la página de
[releases](https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest)
y elige el fichero para tu plataforma:

| Plataforma | Archivo | Instalación |
| --- | --- | --- |
| macOS Apple Silicon (M1/M2/M3/M4) | `factutpv-agent-darwin-arm64.pkg` | Doble clic → Continuar → Instalar |
| macOS Intel | `factutpv-agent-darwin-amd64.pkg` | Doble clic → Continuar → Instalar |
| Windows 10/11 (x64) | `factutpv-agent-windows-amd64.msi` | Doble clic → Siguiente → Instalar |
| Debian / Ubuntu / Mint | `factutpv-agent-linux-amd64.deb` | `sudo apt install ./archivo.deb` |
| Fedora / RHEL / openSUSE | `factutpv-agent-linux-amd64.rpm` | `sudo dnf install ./archivo.rpm` |
| Android 8.0 (API 26) a Android 17 (API 37) | [`factutpv-agent-android.apk`](https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/factutpv-agent-android.apk) | Descarga el APK y sigue los pasos de Android indicados abajo |

Los binarios "raw" (`factutpv-agent-<os>-<arch>`) también se publican
para quien prefiera empaquetar manualmente. Su SHA-256 está en
`releases.json`.

### Android

La app requiere **Android 8.0 (API 26) o posterior** y es compatible hasta
**Android 17 (API 37)**. Descarga el APK de la [última release estable](https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/factutpv-agent-android.apk):

1. Abre el enlace desde el teléfono y descarga `factutpv-agent-android.apk`.
2. Si Android lo solicita, permite a **GitHub** o al navegador que estás
   usando instalar aplicaciones desconocidas. En algunos dispositivos el
   ajuste aparece en **Ajustes → Aplicaciones → Acceso especial → Instalar
   aplicaciones desconocidas**; el nombre puede variar por fabricante.
3. Abre el APK descargado y confirma **Instalar** en el diálogo del sistema.
   Si Android muestra un flujo avanzado para instalar apps de un desarrollador
   no verificado, sigue las indicaciones del sistema. La distribución directa
   desde GitHub continúa disponible mediante sideloading; la verificación del
   desarrollador y los pasos de Android se despliegan por fases y pueden variar
   según región y dispositivo. Consulta la
   [información oficial sobre verificación de desarrolladores de Android](https://developer.android.com/developer-verification).
4. Abre FactuTPV Agent. Acepta las notificaciones y el acceso a la red local,
   USB o Bluetooth cuando Android los solicite y los necesites para el uso
   previsto. USB y Bluetooth dependen del periférico y de los permisos que
   ofrezca el dispositivo.
5. En la app, inicia la vinculación. En otra pestaña, inicia sesión en
   [factutpv.es](https://factutpv.es), entra en **Ajustes → Agentes → Vincular
   nuevo** e introduce el código que muestra la app.

Tras reiniciar el teléfono, la app vuelve a iniciar el agente como un
**servicio en primer plano**; Android muestra una notificación mientras está
activo. Si Android o el fabricante retrasa o limita el arranque, abre la app.
Si usas **Forzar detención** desde los ajustes del sistema, Android mantiene la
app detenida hasta que vuelvas a abrirla.

Para actualizar, usa la opción de actualización dentro de la app. La descarga
se valida con la firma de la app y Android muestra su confirmación de
instalación; acepta ese diálogo para completar la actualización.

La release incluye `SHA256SUMS` con el SHA-256 del APK. Para comprobarlo desde
un ordenador, descarga `SHA256SUMS` y el APK de la misma release y ejecuta
`grep ' factutpv-agent-android.apk$' SHA256SUMS | sha256sum -c -` en la carpeta
que contiene ambos ficheros. En macOS sustituye `sha256sum` por `shasum -a 256`.
En Windows PowerShell, compara la salida de
`Get-FileHash .\factutpv-agent-android.apk -Algorithm SHA256` con la entrada
correspondiente de `SHA256SUMS`.

---

## ¿Qué hace el agente?

El agente es un daemon que corre en un ordenador dentro de tu red
local y hace de puente entre el navegador (tu TPV en
[factutpv.es](https://factutpv.es)) y **cualquier impresora
térmica ESC/POS**:

- **USB** (cable directo; en Windows sin necesidad de Zadig)
- **Red LAN / WiFi** (TCP:9100, Epson ePOS, Star WebPRNT)
- **Bluetooth** (Linux)
- **Impresoras instaladas en Windows** (vía el spooler nativo)
- **Auto-descubrimiento** — pulsa un botón y encuentra todas las
  impresoras accesibles en tu red

El navegador le manda los bytes del ticket, el agente los
reenvía a la impresora. Zero latencia, funciona también cuando
la pestaña del TPV está cerrada (el backend manda la comanda
vía WebSocket a tu agente).

---

## Primeros pasos tras instalar

1. El panel de administración se abre automáticamente en
   [http://localhost:17777/admin](http://localhost:17777/admin).
   Verás un código de 6 dígitos grande y centrado.
2. En otra pestaña ve a [factutpv.es](https://factutpv.es),
   inicia sesión, y navega a **Ajustes → Agentes → Vincular nuevo**.
3. Teclea el código de 6 dígitos, pulsa **Vincular**, y el panel
   del agente pasará de "Sin vincular" a "Conectado".
4. Pulsa **Descubrir impresoras** en el panel. Selecciona la tuya
   de la lista y pulsa **Test** para imprimir un ticket de prueba.

---

## Troubleshooting

### macOS: "no se puede abrir porque Apple no puede comprobar..."

Esto lo muestra macOS en **cualquier** aplicación que no esté firmada
con un certificado de Apple Developer. Dos opciones:

**Opción A (recomendada)**: usa el one-liner. El script hace el
`xattr -d com.apple.quarantine` por ti.

**Opción B**: si descargaste el `.pkg` a mano desde Finder, botón
derecho sobre el `.pkg` → **Abrir** → sale el mismo diálogo pero
esta vez con botón **Abrir**. La segunda vez ya no preguntará.

### Windows: "Windows ha protegido tu PC"

SmartScreen bloquea ejecutables sin firma EV hasta acumular
reputación en su telemetría. Solución temporal: click en **Más
información** → **Ejecutar de todas formas**. Solución definitiva:
firmaremos con un cert EV la próxima release.

### Linux: `systemctl status factutpv-agent` muestra "failed"

Los errores más comunes:

```bash
# Ver el log detallado:
sudo journalctl -u factutpv-agent -n 50 --no-pager

# Editar la config (falta secret, IP de printer errónea, etc.):
sudo -g factutpv nano /etc/factutpv-agent/config.json

# Reiniciar tras editar:
sudo systemctl restart factutpv-agent
```

Si sigue sin funcionar, adjunta el output de `journalctl` al enviar
soporte a soporte@factutpv.es.

---

## Para desinstalar

### macOS / Linux

```bash
curl -sSL https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.sh | bash -s -- uninstall
```

### Windows (PowerShell admin)

```powershell
iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1 | iex
# Y después, en la misma sesión:
iex "iwr -useb https://cdn.jsdelivr.net/gh/ulisesbaena/factutpv-agent-releases@main/install.ps1; factutpv-uninstall"
```

O manualmente desde "Agregar o quitar programas".

---

## Verificar checksums

Cada release incluye:

- `SHA256SUMS`, consumido automáticamente por los instaladores de un comando
  para detectar corrupción y desincronización.
- `releases.json`, cuyo manifiesto Ed25519 firmado cubre tanto binarios raw
  como instaladores y es verificado por el auto-updater del agente.

Para verificar manualmente:

```bash
# Descarga el manifest
curl -L -o /tmp/releases.json https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/releases.json

# Descarga el binario
curl -L -o /tmp/bin https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/factutpv-agent-darwin-arm64

# Compara:
shasum -a 256 /tmp/bin
# y busca el mismo hash dentro de /tmp/releases.json o SHA256SUMS
```

Los one-liners fallan cerrado si falta `SHA256SUMS`, la entrada del
instalador está duplicada o el hash descargado no coincide.

`SHA256SUMS` y el instalador se alojan en la misma release, por lo que esta
comparación no autentica al publicador ante un compromiso del canal. Los
one-liners todavía no verifican la firma Ed25519 de `releases.json`, y la
firma nativa/notarización de los paquetes sigue pendiente.

### Orden de despliegue de este contrato

El instalador estricto requiere que la release estable más reciente ya
publique `SHA256SUMS`. Por eso el orden seguro es: fusionar primero el
pipeline privado del agente, publicar y comprobar una release estable, y
solo entonces fusionar los cambios de `install.sh` / `install.ps1` de este
repositorio. Invertir ese orden bloquearía temporalmente instalaciones
nuevas, de forma deliberada y segura.

---

## Soporte

- Portal: https://factutpv.es
- Email: soporte@factutpv.es
- Bug reports del agente: envía el contenido de `journalctl -u
  factutpv-agent -n 200` (Linux) o `/var/log/factutpv-agent/stdout.log`
  (macOS) junto con tu descripción del problema.
