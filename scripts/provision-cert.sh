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

if [[ -z "${CERTBOT_EMAIL:-}" || -z "${PRIMARY_HOSTNAME:-}" || -z "${HOSTNAMES:-}" ]]; then
  echo "CERTBOT_EMAIL, PRIMARY_HOSTNAME, and HOSTNAMES must be set in ${ROOT_DIR}/.env"
  exit 1
fi

if [[ "${CLOUDFLARE_DNS_API_TOKEN:-}" == replace-* ]]; then
  echo "Replace CLOUDFLARE_DNS_API_TOKEN in ${ROOT_DIR}/.env before requesting a certificate."
  exit 1
fi

if [[ ! -f secrets/cloudflare.ini ]]; then
  echo "Missing ${ROOT_DIR}/secrets/cloudflare.ini"
  exit 1
fi

mkdir -p certbot/etc/letsencrypt certbot/var/lib/letsencrypt certs

declare -a domains
IFS=',' read -ra domains <<< "${HOSTNAMES}"
cert_args=()
for raw_domain in "${domains[@]}"; do
  domain="$(printf '%s' "${raw_domain}" | xargs)"
  [[ -n "${domain}" ]] && cert_args+=("-d" "${domain}")
done

if [[ ${#cert_args[@]} -eq 0 ]]; then
  echo "HOSTNAMES did not produce any certificate names."
  exit 1
fi

docker run --rm \
  -v "${ROOT_DIR}/certbot/etc/letsencrypt:/etc/letsencrypt" \
  -v "${ROOT_DIR}/certbot/var/lib/letsencrypt:/var/lib/letsencrypt" \
  -v "${ROOT_DIR}/secrets/cloudflare.ini:/cloudflare.ini:ro" \
  "certbot/dns-cloudflare:${CERTBOT_IMAGE_TAG:-latest}" \
  certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  --agree-tos \
  --non-interactive \
  --keep-until-expiring \
  --cert-name "${PRIMARY_HOSTNAME}" \
  --email "${CERTBOT_EMAIL}" \
  "${cert_args[@]}"

"${ROOT_DIR}/scripts/sync-certs.sh"
