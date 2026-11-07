#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_root=$(mktemp -d)
server_log="$fixture_root/http.log"
port=18777
checkout_sha=3d3c42e5aac5ba805825da76410c181273ba90b1
pwsh_image='mcr.microsoft.com/powershell:7.4-debian-12@sha256:206a748b34deec1b64553fcfa92294fc871c2df5855e9f340df172756bef201f'

require_before() {
  local file=$1 first=$2 second=$3 first_line second_line
  first_line=$(grep -nF "$first" "$file" | head -1 | cut -d: -f1)
  second_line=$(grep -nF "$second" "$file" | head -1 | cut -d: -f1)
  [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]]
}

require_readme_text() {
  local text=$1
  if ! grep -Fq "$text" "$repo_root/README.md"; then
    echo "README Android download contract is missing: $text" >&2
    exit 1
  fi
}

grep -Fq "actions/checkout@$checkout_sha" "$repo_root/.github/workflows/ci.yml"
grep -Fq "$pwsh_image" "$repo_root/.github/workflows/ci.yml"
require_readme_text 'factutpv-agent-android.apk'
require_readme_text 'https://github.com/ulisesbaena/factutpv-agent-releases/releases/latest/download/factutpv-agent-android.apk'
require_readme_text 'Android 8.0 (API 26)'
require_readme_text 'Android 17 (API 37)'
require_readme_text 'el navegador o la app desde la que descargaste el APK'
require_readme_text 'flujo avanzado para instalar apps de un desarrollador'
require_readme_text 'Ajustes → Impresoras → Agentes → Vincular'
require_readme_text 'Tras reiniciar el teléfono'
require_readme_text 'servicio en primer plano'
require_readme_text 'Forzar detención'
require_readme_text 'firma de la app'
require_readme_text 'confirmación de'
require_readme_text '`SHA256SUMS` con el SHA-256 del APK'
require_readme_text "grep ' factutpv-agent-android.apk$' SHA256SUMS | sha256sum -c -"
require_before "$repo_root/install.sh" \
  'curl -fsSL "$RELEASE_BASE/SHA256SUMS"' 'DL_URL="$RELEASE_BASE/$ASSET"'
require_before "$repo_root/install.ps1" \
  'Invoke-WebRequest -Uri "$releaseBase/SHA256SUMS"' '$url = "$releaseBase/$assetName"'

cleanup() {
  if [[ -n "${server_pid:-}" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$fixture_root"
}
trap cleanup EXIT

for case_name in good bad; do
  mkdir -p "$fixture_root/$case_name"
  printf 'fixture-msi-%s\n' "$case_name" > "$fixture_root/$case_name/factutpv-agent-windows-amd64.msi"
  printf 'fixture-deb-%s\n' "$case_name" > "$fixture_root/$case_name/factutpv-agent-linux-amd64.deb"
  printf 'fixture-pkg-%s\n' "$case_name" > "$fixture_root/$case_name/factutpv-agent-darwin-arm64.pkg"
done

for asset in \
  factutpv-agent-windows-amd64.msi \
  factutpv-agent-linux-amd64.deb \
  factutpv-agent-darwin-arm64.pkg; do
  hash=$(sha256sum "$fixture_root/good/$asset" | awk '{print $1}')
  printf '%s  %s\n' "$hash" "$asset" >> "$fixture_root/good/SHA256SUMS"
  printf '%064d  %s\n' 0 "$asset" >> "$fixture_root/bad/SHA256SUMS"
done

python3 "$repo_root/tests/installer_fixture_server.py" \
  --root "$fixture_root" --port "$port" >"$server_log" 2>&1 &
server_pid=$!
for _ in $(seq 1 50); do
  if curl -fsSL "http://127.0.0.1:$port/good/releases/latest/download/SHA256SUMS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
curl -fsSL "http://127.0.0.1:$port/good/releases/latest/download/SHA256SUMS" >/dev/null

FACTUTPV_VERIFY_ONLY=1 \
FACTUTPV_INSTALL_BASE="http://127.0.0.1:$port/good/releases/latest/download" \
  bash "$repo_root/install.sh"

if FACTUTPV_VERIFY_ONLY=1 \
   FACTUTPV_INSTALL_BASE="http://127.0.0.1:$port/bad/releases/latest/download" \
     bash "$repo_root/install.sh"; then
  echo "POSIX installer accepted a mismatched checksum" >&2
  exit 1
fi

run_pwsh() {
  local case_name=$1
  local docker_host=127.0.0.1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    docker_host=host.docker.internal
  fi
  docker run --rm --network host \
    --env FACTUTPV_VERIFY_ONLY=1 \
    --env "FACTUTPV_INSTALL_BASE=http://$docker_host:$port/$case_name/releases/latest/download" \
    --env TEMP=/tmp \
    --volume "$repo_root:/repo:ro" \
    "$pwsh_image" \
    pwsh -NoLogo -NoProfile -NonInteractive -File /repo/install.ps1
}

run_pwsh good
if run_pwsh bad; then
  echo "PowerShell installer accepted a mismatched checksum" >&2
  exit 1
fi

echo "installer integrity tests: ok"
