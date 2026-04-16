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

if [[ "${CLOUDFLARE_DNS_API_TOKEN:-}" == replace-* ]]; then
  echo "Replace CLOUDFLARE_DNS_API_TOKEN in ${ROOT_DIR}/.env before renewing the certificate."
  exit 1
fi

if [[ ! -f secrets/cloudflare.ini ]]; then
  echo "Missing ${ROOT_DIR}/secrets/cloudflare.ini"
  exit 1
fi

docker run --rm \
  -v "${ROOT_DIR}/certbot/etc/letsencrypt:/etc/letsencrypt" \
  -v "${ROOT_DIR}/certbot/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -v "${ROOT_DIR}/secrets/cloudflare.ini:/cloudflare.ini:ro" \
  "certbot/dns-cloudflare:${CERTBOT_IMAGE_TAG:-latest}" \
  renew \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60

"${ROOT_DIR}/scripts/sync-certs.sh"
