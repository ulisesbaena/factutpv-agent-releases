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

Los binarios "raw" (`factutpv-agent-<os>-<arch>`) también se publican
para quien prefiera empaquetar manualmente. Su SHA-256 está en
`releases.json`.

---

## ¿Qué hace el agente?

El agente es un daemon que corre en un ordenador dentro de tu red
local y hace de puente entre el navegador (tu TPV en
[app.factutpv.es](https://app.factutpv.es)) y **cualquier impresora
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
2. En otra pestaña ve a [app.factutpv.es](https://app.factutpv.es),
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

Cada release incluye un fichero `releases.json` con los SHA-256
de los binarios raw. Para verificar:

```bash
# Descarga el manifest
curl -L -o /tmp/releases.json https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/releases.json

# Descarga el binario
curl -L -o /tmp/bin https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/factutpv-agent-darwin-arm64

# Compara:
shasum -a 256 /tmp/bin
# y busca el mismo hash dentro de /tmp/releases.json
```

Los instaladores (`.pkg`, `.msi`, `.deb`, `.rpm`) no llevan
checksum firmado en `releases.json` todavía; se publicarán en la
siguiente revisión del pipeline.

---

## Soporte

- Portal: https://factutpv.es
- Email: soporte@factutpv.es
- Bug reports del agente: envía el contenido de `journalctl -u
  factutpv-agent -n 200` (Linux) o `/var/log/factutpv-agent/stdout.log`
  (macOS) junto con tu descripción del problema.
