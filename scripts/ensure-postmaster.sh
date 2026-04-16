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

postmaster_address="${POSTMASTER}@${DOMAIN}"
admin_address="${INITIAL_ADMIN_ACCOUNT}@${INITIAL_ADMIN_DOMAIN}"

if [[ "${postmaster_address}" == "${admin_address}" ]]; then
  echo "POSTMASTER already points at the initial admin user."
  exit 0
fi

docker compose exec -T admin flask mailu alias "${POSTMASTER}" "${DOMAIN}" "${admin_address}"
