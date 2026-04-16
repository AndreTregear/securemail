#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created ${ROOT_DIR}/.env"
  echo "Edit the domain, hostnames, and Cloudflare token, then rerun this script."
  exit 1
fi

set -a
. ./.env
set +a

require_value() {
  local key="$1"
  local value="${!key:-}"
  if [[ -z "${value}" ]]; then
    echo "Missing required setting: ${key}"
    exit 1
  fi
}

replace_env_value() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')"
  sed -i "s/^${key}=.*/${key}=${escaped}/" .env
}

generate_secret() {
  openssl rand -hex 32
}

generate_password() {
  openssl rand -base64 24 | tr -d '\n' | tr '/+' '_-'
}

require_value DOMAIN
require_value PRIMARY_HOSTNAME
require_value HOSTNAMES
require_value INITIAL_ADMIN_ACCOUNT
require_value INITIAL_ADMIN_DOMAIN
require_value CERTBOT_EMAIL
require_value CLOUDFLARE_DNS_API_TOKEN

if [[ "${DOMAIN}" == "example.com" || "${PRIMARY_HOSTNAME}" == "mail.example.com" ]]; then
  echo "Replace the example domain values in ${ROOT_DIR}/.env before bootstrapping."
  exit 1
fi

if [[ "${CLOUDFLARE_DNS_API_TOKEN}" == replace-* ]]; then
  echo "Replace CLOUDFLARE_DNS_API_TOKEN in ${ROOT_DIR}/.env before bootstrapping."
  exit 1
fi

generated=0
generated_file="${ROOT_DIR}/bootstrap.generated"
umask 077
: > "${generated_file}"

for key in SECRET_KEY API_TOKEN INITIAL_ADMIN_PW; do
  value="${!key:-}"
  if [[ -z "${value}" || "${value}" == replace-* ]]; then
    if [[ "${key}" == "INITIAL_ADMIN_PW" ]]; then
      value="$(generate_password)"
    else
      value="$(generate_secret)"
    fi
    replace_env_value "${key}" "${value}"
    printf '%s=%s\n' "${key}" "${value}" >> "${generated_file}"
    generated=1
  fi
done

mkdir -p \
  certbot/etc/letsencrypt \
  certbot/var/lib/letsencrypt \
  certs \
  data \
  dkim \
  filter \
  mail \
  mailqueue \
  redis \
  secrets \
  webmail \
  overrides/nginx \
  overrides/dovecot \
  overrides/postfix \
  overrides/rspamd \
  overrides/roundcube

if [[ ! -f secrets/cloudflare.ini ]]; then
  cat > secrets/cloudflare.ini <<EOF
dns_cloudflare_api_token = ${CLOUDFLARE_DNS_API_TOKEN}
EOF
fi
chmod 600 secrets/cloudflare.ini

docker compose --env-file .env config >/dev/null
docker compose pull
"${ROOT_DIR}/scripts/provision-cert.sh"
docker compose up -d

if [[ "${POSTMASTER}" != "${INITIAL_ADMIN_ACCOUNT}" ]]; then
  "${ROOT_DIR}/scripts/ensure-postmaster.sh" || true
fi

echo "Mailu stack started."
echo
echo "Endpoints:"
echo "  Admin:    http://localhost:${HTTP_PORT}${WEB_ADMIN}"
echo "  Webmail:  http://localhost:${HTTP_PORT}${WEB_WEBMAIL}"
echo "  API docs: http://localhost:${HTTP_PORT}${WEB_API}/"
echo
echo "Next:"
echo "  1. Tunnel webmail.<your-domain> to http://localhost:${HTTP_PORT}"
echo "  2. Add mail DNS records for ${DOMAIN}"
echo "  3. Connect an MCP client using ${ROOT_DIR}/mcp-server.js"
echo
if [[ "${generated}" -eq 1 ]]; then
  echo "Generated credentials were written to ${generated_file}"
fi
