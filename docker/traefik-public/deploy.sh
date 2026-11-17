#!/bin/bash
mkdir -p "${BAK_CFG_DIR}"/traefik-public/logs
mkdir -p "${BAK_CFG_DIR}"/traefik-public/dynamic_cfg
touch "${BAK_CFG_DIR}"/traefik-public/acme.json
chmod 600 "${BAK_CFG_DIR}"/traefik-public/acme.json
docker compose -f "${COMPOSE_DIR}/traefik-public/docker-compose.yml" up -d
