#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 user@example.com 'new-password'"
  exit 1
fi

email="$1"
password="$2"
localpart="${email%@*}"
domain="${email#*@}"

if [[ "${localpart}" == "${domain}" ]]; then
  echo "Expected an email address like user@example.com"
  exit 1
fi

docker compose exec -T admin flask mailu password "${localpart}" "${domain}" "${password}"
