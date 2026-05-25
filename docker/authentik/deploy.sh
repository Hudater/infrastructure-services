#!/bin/bash
CREATE_DIRS=( "${BAK_CFG_DIR}"/authentik/{authentik-worker-data,authentik-server-data,authentik_server-media,authentik_server_custom-templates,authentik_worker-media,authentik_worker-certs,authentik_worker_custom-templates} )
mkdir -p "${CREATE_DIRS[@]}"
# ls -alh "$BAK_CFG_DIR"/authentik/ "$DB_CFG_DIR"
# ls -alh "${CREATE_DIRS[@]}"
docker compose up -d
