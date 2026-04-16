#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ ! -f .env ]]; then
  echo "Missing ${ROOT_DIR}/.env"
  exit 1
fi

set -a
. ./.env
set +a

SOURCE_DIR="${ROOT_DIR}/certbot/etc/letsencrypt/live/${PRIMARY_HOSTNAME}"
if [[ ! -f "${SOURCE_DIR}/fullchain.pem" || ! -f "${SOURCE_DIR}/privkey.pem" ]]; then
  echo "Certificate files not found under ${SOURCE_DIR}"
  exit 1
fi

mkdir -p certs
cp "${SOURCE_DIR}/fullchain.pem" certs/${TLS_CERT_FILENAME:-cert.pem}
cp "${SOURCE_DIR}/privkey.pem" certs/${TLS_KEYPAIR_FILENAME:-key.pem}
chmod 600 certs/${TLS_KEYPAIR_FILENAME:-key.pem}

if docker compose ps -q front >/dev/null 2>&1 && [[ -n "$(docker compose ps -q front)" ]]; then
  docker compose restart front imap smtp
fi

echo "Synchronized Mailu certificates into ${ROOT_DIR}/certs"
