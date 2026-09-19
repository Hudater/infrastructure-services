#!/bin/bash
mkdir -p "${BAK_CFG_DIR}/karakeep/data"
mkdir -p "${BAK_CFG_DIR}/karakeep/karakeep-dash"
docker compose up -d --force-recreate


MODEL="${EMBEDDING_MODEL:-qwen3-embedding:0.6b}"

echo "waiting for karakeep-ollama..."
for i in $(seq 1 60); do
  if docker exec karakeep-ollama ollama list >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "karakeep-ollama not ready after 120s" >&2
    exit 1
  fi
  sleep 2
done

if ! docker exec karakeep-ollama ollama list | awk 'NR>1 {print $1}' | grep -q "^${MODEL}"; then
  docker exec karakeep-ollama ollama pull "${MODEL}"
fi
