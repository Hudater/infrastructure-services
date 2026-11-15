#!/bin/bash
set -euo pipefail

# ============================================================================
# deploy.sh — Unified LXC/bare-metal installer for Technitium DNS
#
# Auto-detects whether it's running on a Proxmox VE host or a regular Linux
# host with LXD, loads the appropriate resource config, and installs accordingly.
#
# Usage:
#   ./deploy.sh              # auto-detect environment
#   ./deploy.sh --pve        # force Proxmox mode
#   ./deploy.sh --baremetal  # force bare metal mode
#   ./deploy.sh --dry-run    # show what would happen without executing
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"
PARSER_DIR="$(cd "${SCRIPT_DIR}/../resource-parser" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

DRY_RUN=false
FORCE_MODE=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case $arg in
    --pve)       FORCE_MODE="pve" ;;
    --baremetal) FORCE_MODE="baremetal" ;;
    --dry-run)   DRY_RUN=true ;;
    --help|-h)
      head -16 "$0" | tail -11
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown argument: $arg${NC}" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------
log()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()  { echo -e "${RED}[error]${NC} $*" >&2; }
info() { echo -e "${CYAN}[info]${NC}  $*"; }

run_cmd() {
  if $DRY_RUN; then
    info "DRY RUN: $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Check for uv
# ---------------------------------------------------------------------------
check_uv() {
  if ! command -v uv &>/dev/null; then
    err "uv is not installed. Install it first:"
    err "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Parse resource YAML via central parser
# ---------------------------------------------------------------------------
parse_resource() {
  local yaml_file="$1"
  local key="${2:-}"

  if [[ ! -f "$yaml_file" ]]; then
    err "Resource file not found: $yaml_file"
    exit 1
  fi

  if [[ -n "$key" ]]; then
    uv run "${PARSER_DIR}/parse.py" "$yaml_file" "$key"
  else
    uv run "${PARSER_DIR}/parse.py" "$yaml_file"
  fi
}

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------
detect_environment() {
  if [[ -n "$FORCE_MODE" ]]; then
    echo "$FORCE_MODE"
    return
  fi

  # Proxmox VE detection: check for PVE-specific paths and commands
  if [[ -d "/etc/pve" ]] && command -v pveversion &>/dev/null; then
    echo "pve"
  else
    echo "baremetal"
  fi
}

# ---------------------------------------------------------------------------
# Proxmox VE install — runs community script from the PVE host
# ---------------------------------------------------------------------------
install_pve() {
  local resource_file="${RESOURCE_DIR}/pve.yaml"

  log "Loading Proxmox resource config..."
  local script_url
  script_url=$(parse_resource "$resource_file" "install.community_script")

  local ct_id hostname cpu ram disk
  ct_id=$(parse_resource "$resource_file" "container.id")
  hostname=$(parse_resource "$resource_file" "container.hostname")
  cpu=$(parse_resource "$resource_file" "resources.cpu")
  ram=$(parse_resource "$resource_file" "resources.ram")
  disk=$(parse_resource "$resource_file" "resources.disk")

  local port protocol
  port=$(parse_resource "$resource_file" "access.port")
  protocol=$(parse_resource "$resource_file" "access.protocol")

  echo ""
  info "╔══════════════════════════════════════════╗"
  info "║  Proxmox VE LXC Installation             ║"
  info "╠══════════════════════════════════════════╣"
  info "║  Service:   Technitium DNS               ║"
  info "║  CT ID:     ${ct_id}                     ║"
  info "║  Hostname:  ${hostname}                  ║"
  info "║  CPU:       ${cpu} core(s)               ║"
  info "║  RAM:       ${ram} MB                    ║"
  info "║  Disk:      ${disk} GB                   ║"
  info "╚══════════════════════════════════════════╝"
  echo ""

  log "Running community script from: ${script_url}"
  warn "The script will prompt you for configuration."
  warn "Use the values above as reference, or accept defaults."
  echo ""

  run_cmd bash -c "$(curl -fsSL "$script_url")"

  echo ""
  log "Installation complete!"
  log "Access Technitium DNS at: ${protocol}://<container-ip>:${port}"
}

# ---------------------------------------------------------------------------
# LXD install — creates an LXC container on a non-Proxmox Linux host
# ---------------------------------------------------------------------------
install_baremetal() {
  local resource_file="${RESOURCE_DIR}/lxc.yaml"

  log "Loading LXD resource config..."
  local ct_name image cpu ram disk bridge ip install_url method port protocol
  ct_name=$(parse_resource "$resource_file" "container.name")
  image=$(parse_resource "$resource_file" "container.image")
  cpu=$(parse_resource "$resource_file" "resources.cpu")
  ram=$(parse_resource "$resource_file" "resources.ram")
  disk=$(parse_resource "$resource_file" "resources.disk")
  bridge=$(parse_resource "$resource_file" "network.bridge")
  ip=$(parse_resource "$resource_file" "network.ip")
  install_url=$(parse_resource "$resource_file" "install.url")
  method=$(parse_resource "$resource_file" "install.method")
  port=$(parse_resource "$resource_file" "access.port")
  protocol=$(parse_resource "$resource_file" "access.protocol")

  echo ""
  info "╔══════════════════════════════════════════╗"
  info "║  LXD Container Installation              ║"
  info "╠══════════════════════════════════════════╣"
  info "║  Service:   Technitium DNS               ║"
  info "║  Container: ${ct_name}                   ║"
  info "║  Image:     ${image}                     ║"
  info "║  CPU:       ${cpu} core(s)               ║"
  info "║  RAM:       ${ram}                       ║"
  info "║  Disk:      ${disk}                      ║"
  info "║  Network:   ${bridge} / ${ip}            ║"
  info "╚══════════════════════════════════════════╝"
  echo ""

  # Check lxc is available
  if ! command -v lxc &>/dev/null; then
    err "lxc command not found. Install LXD first:"
    err "  sudo snap install lxd && lxd init"
    exit 1
  fi

  # Check container doesn't already exist
  if lxc info "${ct_name}" &>/dev/null; then
    err "Container '${ct_name}' already exists. Remove it first:"
    err "  lxc delete ${ct_name} --force"
    exit 1
  fi

  # Launch container
  log "Launching container '${ct_name}' from image '${image}'..."
  run_cmd lxc launch "${image}" "${ct_name}"

  # Apply resource limits
  log "Applying resource limits..."
  if [[ "${cpu}" != "0" ]]; then
    run_cmd lxc config set "${ct_name}" limits.cpu "${cpu}"
  fi
  run_cmd lxc config set "${ct_name}" limits.memory "${ram}"
  run_cmd lxc config device override "${ct_name}" root size="${disk}"

  # Wait for container to get an IP address
  log "Waiting for container to get an IP address..."
  local retries=20
  local ct_ip=""
  while [[ -z "$ct_ip" && $retries -gt 0 ]]; do
    ct_ip=$(lxc list "${ct_name}" --format csv -c 4 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
    if [[ -z "$ct_ip" ]]; then
      sleep 2
      retries=$((retries - 1))
    fi
  done

  if [[ -z "$ct_ip" ]]; then
    err "Container never received an IP address. Check LXD network config."
    err "  lxc list ${ct_name}"
    err "  lxc network show lxdbr0"
    exit 1
  fi
  log "Container IP: ${ct_ip}"

  # Verify outbound internet connectivity via TCP (more reliable than ICMP ping)
  log "Verifying outbound internet connectivity..."
  retries=10
  local connected=false
  while [[ "$connected" != "true" && $retries -gt 0 ]]; do
    if lxc exec "${ct_name}" -- sh -c "nc -zw3 download.technitium.com 443" &>/dev/null; then
      connected=true
    else
      sleep 2
      retries=$((retries - 1))
    fi
  done

  if [[ "$connected" != "true" ]]; then
    err "Container cannot reach download.technitium.com:443."
    err "Check LXD bridge NAT/forwarding: lxc network show lxdbr0"
    exit 1
  fi

  # Run install script inside the container
  log "Running install script inside '${ct_name}'..."
  case "$method" in
    official)
      run_cmd lxc exec "${ct_name}" -- bash -c "curl -sSL '${install_url}' | bash"
      ;;
    *)
      err "Unknown install method: ${method}"
      exit 1
      ;;
  esac

  echo ""
  log "Installation complete!"
  log "Shell into container: lxc exec ${ct_name} -- bash"
  log "Access Technitium DNS at: ${protocol}://${ct_ip:-<container-ip>}:${port}"
}

# ============================================================================
# Main
# ============================================================================
main() {
  check_uv

  local env
  env=$(detect_environment)

  log "Detected environment: ${env}"
  echo ""

  case "$env" in
    pve)
      install_pve
      ;;
    baremetal)
      install_baremetal
      ;;
    *)
      err "Unknown environment: ${env}"
      exit 1
      ;;
  esac
}

main
