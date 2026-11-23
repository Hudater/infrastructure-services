#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export MCPHUB_STATE_DIR="${MCPHUB_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mcphub}"
mkdir -p -m 700 "$MCPHUB_STATE_DIR"
if [[ ! -f "$MCPHUB_STATE_DIR/mcp_settings.json" ]]; then
  python3 configure.py "${BAK_CFG_DIR:?}/mcphub/mcp_settings.json" "$MCPHUB_STATE_DIR/mcp_settings.json"
fi
docker compose up -d
