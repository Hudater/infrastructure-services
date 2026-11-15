# Technitium DNS

Self-hosted authoritative and recursive DNS server with ad-blocking.

## Quick Deploy

```bash
# Auto-detects PVE vs bare metal
./deploy.sh

# Force a specific mode
./deploy.sh --pve
./deploy.sh --baremetal

# Preview without executing
./deploy.sh --dry-run
```

## Access

- **Web UI**: `http://<IP>:5380`
- **DNS**: Port `53` (TCP/UDP)

## Structure

```
technitium-dns/
├── deploy.sh                # Unified installer (auto-detects environment)
├── resources/
│   ├── pve.yaml             # Proxmox LXC resource config
│   └── baremetal.yaml       # Bare Linux resource config
├── config/                  # Post-install application config
└── README.md
```

## Resource Configuration

Edit the YAML files in `resources/` **before** running deploy to customize CPU, RAM, disk, network, etc.

## Updating

- **PVE LXC**: Log into the container console and run `update`
- **Bare metal**: Re-run the official install script (it handles updates)

## Links

- [Technitium DNS](https://technitium.com/dns/)
- [Community Script](https://community-scripts.org/categories?category=adblock-and-dns&preview=technitiumdns)
