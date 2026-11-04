#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_root=$(mktemp -d)
server_log="$fixture_root/http.log"
port=18777

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

python3 -m http.server "$port" --bind 0.0.0.0 --directory "$fixture_root" >"$server_log" 2>&1 &
server_pid=$!
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$port/good/SHA256SUMS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
curl -fsS "http://127.0.0.1:$port/good/SHA256SUMS" >/dev/null

FACTUTPV_VERIFY_ONLY=1 \
FACTUTPV_INSTALL_BASE="http://127.0.0.1:$port/good" \
  bash "$repo_root/install.sh"

if FACTUTPV_VERIFY_ONLY=1 \
   FACTUTPV_INSTALL_BASE="http://127.0.0.1:$port/bad" \
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
    --env "FACTUTPV_INSTALL_BASE=http://$docker_host:$port/$case_name" \
    --env TEMP=/tmp \
    --volume "$repo_root:/repo:ro" \
    mcr.microsoft.com/powershell:7.4-debian-12 \
    pwsh -NoLogo -NoProfile -NonInteractive -File /repo/install.ps1
}

run_pwsh good
if run_pwsh bad; then
  echo "PowerShell installer accepted a mismatched checksum" >&2
  exit 1
fi

echo "installer integrity tests: ok"
