#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
root="${MODEL_ROOT:-/mnt/ai/local-models}"
mkdir -p "$root/gguf"
exec 9>"$root/gguf/.download.lock"
flock 9
while read -r alias checksum url; do
  model="$root/gguf/$alias.gguf"
  if [[ ! -s "$model" ]]; then
    curl -fsSL --retry 5 --retry-all-errors --continue-at - "$url" -o "$model.part"
    printf '%s  %s\n' "$checksum" "$model.part" | sha256sum -c -
    mv "$model.part" "$model"
  fi
done < models.txt
