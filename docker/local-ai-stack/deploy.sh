#!/usr/bin/env bash
set -euo pipefail
# CREATE_DIRS=( "${BAK_CFG_DIR}"/local-ai-stack/{multiple,dir,names} "$DB_CFG_DIR"/local-ai-stack "$CFG_DIR"/local-ai-stack )
# mkdir -p "${CREATE_DIRS[@]}"
# ls -alh "$BAK_CFG_DIR"/local-ai-stack/ "$DB_CFG_DIR"
# ls -alh "${CREATE_DIRS[@]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_FILE="${MODELS_FILE:-$SCRIPT_DIR/models.txt}"
CONTAINER="${CONTAINER:-ai-ollama}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
WAIT_INTERVAL="${WAIT_INTERVAL:-5}"
# Fallbacks so `set -u` doesn't fail when env is not exported (original script used bare vars)
BAK_CFG_DIR="${BAK_CFG_DIR:-}"
COMPOSE_DIR="${COMPOSE_DIR:-$(dirname "$SCRIPT_DIR")}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- helpers ---
trim() {
  local s="$1"
  s="${s%$'\r'}"
  s="$(printf '%s' "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  printf '%s' "$s"
}

# Check remote existence via registry.ollama.ai.
# echo: 0=exists, 1=missing, 2=unknown
check_model_exists() {
  local model="$1" name tag path url
  if [[ "$model" == *:* ]]; then
    name="${model%%:*}"; tag="${model##*:}"
  else
    name="$model"; tag="latest"
  fi
  if [[ "$name" == */* ]]; then
    path="$name"
  else
    path="library/$name"
  fi
  url="https://registry.ollama.ai/v2/${path}/manifests/${tag}"

  if command -v curl >/dev/null 2>&1; then
    local code
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "$url" 2>/dev/null || echo "000")"
    case "$code" in
      200) return 0 ;;
      404) return 1 ;;
      *) return 2 ;;
    esac
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO /dev/null --timeout=15 \
      --header="Accept: application/vnd.docker.distribution.manifest.v2+json" "$url" 2>/dev/null; then
      return 0
    else
      # wget can't reliably distinguish 404 vs network error; treat as missing
      # to force explicit user verification, caller lists it as not-found.
      return 1
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 - "$url" <<'PY' 2>/dev/null; then
import sys, urllib.request, urllib.error
url = sys.argv[1]
req = urllib.request.Request(url, headers={"Accept": "application/vnd.docker.distribution.manifest.v2+json"})
try:
    with urllib.request.urlopen(req, timeout=15):
        sys.exit(0)
except urllib.error.HTTPError as e:
    sys.exit(0 if e.code == 200 else (1 if e.code == 404 else 2))
except Exception:
    sys.exit(2)
PY
      return 0
    else
      rc=$?
      return "$rc"
    fi
  else
    return 2
  fi
}

wait_for_ollama() {
  local elapsed=0
  echo "Waiting for $CONTAINER to be healthy (timeout ${WAIT_TIMEOUT}s)..."
  while [ "$elapsed" -lt "$WAIT_TIMEOUT" ]; do
    if docker exec "$CONTAINER" ollama list >/dev/null 2>&1; then
      echo "Ollama is up."
      return 0
    fi
    sleep "$WAIT_INTERVAL"
    elapsed=$((elapsed + WAIT_INTERVAL))
  done
  echo -e "${RED}Timed out waiting for $CONTAINER after ${WAIT_TIMEOUT}s.${NC}" >&2
  return 1
}

# --- 1. load models.txt ---
if [ ! -f "$MODELS_FILE" ]; then
  echo -e "${RED}ERROR: models file not found: $MODELS_FILE${NC}" >&2
  exit 1
fi

MODELS=()
while IFS= read -r line || [ -n "$line" ]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" == \#* ]] && continue
  MODELS+=("$line")
done < "$MODELS_FILE"

if [ "${#MODELS[@]}" -eq 0 ]; then
  echo -e "${RED}ERROR: no models listed in $MODELS_FILE${NC}" >&2
  exit 1
fi

echo "Checking ${#MODELS[@]} model(s) from $MODELS_FILE ..."

# --- 2. existence check: check ALL, even if first fails ---
FOUND=()
MISSING=()
UNKNOWN=()
for m in "${MODELS[@]}"; do
  if check_model_exists "$m"; then
    echo -e "${GREEN}[OK]${NC} $m"
    FOUND+=("$m")
  else
    rc=$?
    if [ "$rc" -eq 1 ]; then
      echo -e "${RED}[MISSING]${NC} $m"
      MISSING+=("$m")
    else
      echo -e "${YELLOW}[UNKNOWN]${NC} $m (could not verify - no curl/wget/python3 or network error)"
      UNKNOWN+=("$m")
    fi
  fi
done

if [ "${#MISSING[@]}" -gt 0 ] || [ "${#UNKNOWN[@]}" -gt 0 ]; then
  echo -e "${RED}ERROR: some models do not exist or could not be verified:${NC}" >&2
  if [ "${#MISSING[@]}" -gt 0 ]; then
    for m in "${MODELS[@]}"; do
      for miss in "${MISSING[@]}"; do
        if [ "$m" = "$miss" ]; then echo -e "${RED}  - $m (not found)${NC}" >&2; fi
      done
    done
  fi
  if [ "${#UNKNOWN[@]}" -gt 0 ]; then
    for m in "${UNKNOWN[@]}"; do echo -e "${YELLOW}  - $m (unknown)${NC}" >&2; done
  fi
  exit 1
fi

echo -e "${GREEN}All ${#MODELS[@]} models exist.${NC}"

# --- 3. confirmation ---
read -r -p "Continue with deploy + pull ${#MODELS[@]} model(s)? [Y/n] " ans || ans=""
ans="$(trim "$ans")"
if [[ "$ans" == [nN] || "$ans" == [nN][oO] ]]; then
  echo "Aborted by user."
  exit 0
fi

# --- 4. deploy ---
docker compose  --env-file "$BAK_CFG_DIR/local-ai-stack/.env" -f "${COMPOSE_DIR}/local-ai-stack/docker-compose.yml" up -d --force-recreate

# --- 5. wait healthy ---
wait_for_ollama

# --- 6. pull (skip + continue on failure) ---
INSTALLED=()
FAILED=()
set +e
for m in "${MODELS[@]}"; do
  echo "Pulling $m ..."
  if docker exec "$CONTAINER" ollama pull "$m"; then
    INSTALLED+=("$m")
  else
    echo -e "${RED}Failed to pull $m, continuing...${NC}" >&2
    FAILED+=("$m")
  fi
done
set -e

# --- 7. final table ---
echo ""
echo "=========== RESULT ==========="
printf "%-35s %s\n" "MODEL" "STATUS"
if [ "${#INSTALLED[@]}" -gt 0 ]; then
  for m in "${INSTALLED[@]}"; do
    # shellcheck disable=SC2059
    printf "${GREEN}%-35s %s${NC}\n" "$m" "installed"
  done
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
  for m in "${FAILED[@]}"; do
    # shellcheck disable=SC2059
    printf "${RED}%-35s %s${NC}\n" "$m" "FAILED"
  done
fi
echo "=============================="
echo "Installed: ${#INSTALLED[@]}, Failed: ${#FAILED[@]}"

if [ "${#FAILED[@]}" -gt 0 ]; then
  exit 1
fi


### Credit: https://askubuntu.com/a/957278
### MAKE SURE TO USE BASH not DASH
## Define array of all dirs to be created like:
# array_dirs=( "${PATH_ENV}/parent_dir/{dir1,dir2{dir2_1, dir2_2}}" "${SECOND_PATH_ENV}"/dir /path )
