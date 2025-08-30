#!/usr/bin/env bash
set -euo pipefail
if ! command -v shfmt > /dev/null 2>&1; then
  echo "shfmt not installed"
  exit 1
fi
shfmt -w pdf-squeeze tests/*.sh scripts/*.sh
