#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export LLAMA_STATE_DIR="${LLAMA_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/llama-cpp}"
if [[ -z "${LLAMA_BIND_IP:-}" ]]; then
  LLAMA_BIND_IP=$(netbird status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["netbirdIp"].split("/", 1)[0])')
fi
export LLAMA_BIND_IP
: "${LLAMA_BIND_IP:?Set LLAMA_BIND_IP or connect NetBird}"
umask 077
mkdir -p "$LLAMA_STATE_DIR"
if [[ ! -s "$LLAMA_STATE_DIR/api-key" ]]; then
  openssl rand -hex 32 > "$LLAMA_STATE_DIR/api-key"
fi
webui_key="$(head -n 1 "$LLAMA_STATE_DIR/api-key")"
if [[ -r "${BAK_CFG_DIR:-}/omniroute/.env" ]]; then
  gateway_key="$(sed -n 's/^OMNI_KEY_LLAMA_CPP=//p' "$BAK_CFG_DIR/omniroute/.env")"
  if [[ -n "$gateway_key" ]]; then
    printf '%s\n%s\n' "$webui_key" "$gateway_key" > "$LLAMA_STATE_DIR/api-key"
  fi
fi
printf 'OPENAI_API_KEYS=%s\n' "$webui_key" > "$LLAMA_STATE_DIR/webui.env"
if [[ "${1:-}" != "--cached" ]]; then ./prepare-models.sh; fi
python3 presets.py "${MODEL_ROOT:-/mnt/ai/local-models}" "$LLAMA_STATE_DIR"
docker compose up -d --pull always --force-recreate llama
for attempt in {1..60}; do
  if curl -fs "http://$LLAMA_BIND_IP:11435/health" >/dev/null; then break; fi
  sleep 2
done
curl -fsS "http://$LLAMA_BIND_IP:11435/health" >/dev/null
if [[ "${1:-}" != "--cached" ]]; then
  docker compose up -d --no-deps --pull always open-webui
fi
