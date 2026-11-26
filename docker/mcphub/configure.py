"""Migrate an existing MCPHub settings file, preserving group IDs and agent keys."""
import json
import os
from pathlib import Path
import sys
import tempfile
import uuid

seed, target = map(Path, sys.argv[1:])
settings = json.loads((target if target.exists() else seed).read_text())
netbird = settings["mcpServers"]["netbird"]
netbird.update(type="streamable-http", url="${NETBIRD_MCP_URL}", protocolNegotiation="legacy",
               headers={"Authorization": "Token ${NETBIRD_API_TOKEN}"},
               description="Official NetBird management MCP")
routing = settings["systemConfig"]["routing"]
routing.update(skipAuth=True, enableGlobalRoute=False, enableGroupNameRoute=True, enableBearerAuth=True)
groups = {item["name"]: item for item in settings["groups"]}
for name, servers in {"docs": ["context7"], "terraform": ["terraform"], "network": ["netbird"],
                      "firewall": ["opnsense"], "source": ["github"], "media": ["arrs"],
                      "virtualization": ["proxmox"], "astro": ["astro"]}.items():
    if name not in groups:
        groups[name] = {"name": name, "id": str(uuid.uuid4()), "owner": "admin"}
    groups[name]["servers"] = [{"name": server, "tools": "all", "prompts": "all", "resources": "all"}
                               for server in servers if server in settings["mcpServers"]]
settings["groups"] = list(groups.values())
if (target.parent / "omniroute.env").is_file():
    settings["mcpServers"].setdefault("omniroute", {
        "type": "streamable-http",
        "url": "http://omniroute:20128/api/mcp/stream",
        "headers": {"Authorization": "Bearer ${OMNIROUTE_MCP_KEY}"},
        "protocolNegotiation": "legacy",
        "owner": "admin",
        "id": str(uuid.uuid4()),
    })
    if "inference" not in groups:
        settings["groups"].append({
            "name": "inference", "id": str(uuid.uuid4()), "owner": "admin",
            "servers": [{
                "name": "omniroute",
                "tools": [
                    "omniroute_get_health", "omniroute_get_combo_metrics", "omniroute_list_combos",
                    "omniroute_check_quota", "omniroute_list_models_catalog",
                ],
                "prompts": [],
                "resources": [],
            }],
        })
with tempfile.NamedTemporaryFile(dir=target.parent, mode="w", delete=False) as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(f.name, target)
