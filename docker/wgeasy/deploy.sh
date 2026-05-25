#!/bin/bash
mkdir -p "${BAK_CFG_DIR}"/wgeasy
docker compose up -d --force-recreate
