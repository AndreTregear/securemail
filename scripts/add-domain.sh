#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 example.com"
  exit 1
fi

docker compose exec -T admin flask mailu domain "$1"
