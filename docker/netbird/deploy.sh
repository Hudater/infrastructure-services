#!/bin/bash
mkdir -p "${BAK_CFG_DIR}"/netbird/certs
docker compose up -d --force-recreate --remove-orphans
