#!/usr/bin/env bash
mkdir -p "${BAK_CFG_DIR}/dozzle-${HOSTNAME}"
docker compose up -d --force-recreate