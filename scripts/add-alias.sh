#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 alias@example.com target1@example.com [target2@example.com ...]"
  exit 1
fi

alias_email="$1"
shift
localpart="${alias_email%@*}"
domain="${alias_email#*@}"

if [[ "${localpart}" == "${domain}" ]]; then
  echo "Expected an alias email like alias@example.com"
  exit 1
fi

destinations="$(IFS=,; echo "$*")"
docker compose exec -T admin flask mailu alias "${localpart}" "${domain}" "${destinations}"
