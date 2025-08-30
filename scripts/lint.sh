#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Controls:
#   VERBOSE=1   → show diffs, detailed output
#   FIX=0       → don't rewrite files (default: rewrite when possible)
VERBOSE="${VERBOSE:-0}"
FIX="${FIX:-1}"

# --- zsh syntax check (quiet unless error) ---
zsh -n "$ROOT/pdf-squeeze"

# --- format bash test scripts ---
if command -v shfmt >/dev/null 2>&1; then
  if [[ "$FIX" = "1" ]]; then
    # Write changes in-place (quiet)
    shfmt -w -i 2 -bn -ci -sr "$ROOT/tests"/*.sh
  else
    # Check mode; show diffs only if verbose
    if [[ "$VERBOSE" = "1" ]]; then
      shfmt -d -i 2 -bn -ci -sr "$ROOT/tests"/*.sh
    else
      # Non-zero exit if changes needed, but don't print full diffs
      if ! shfmt -l -i 2 -bn -ci -sr "$ROOT/tests"/*.sh | grep . >/dev/null; then
        : # clean
      else
        echo "shfmt: files need formatting (rerun with FIX=1 or VERBOSE=1 for details)"
        exit 1
      fi
    fi
  fi
fi

# --- shellcheck (bash tests only; skip zsh main) ---
if command -v shellcheck >/dev/null 2>&1; then
  # Add SC codes you want to silence here if needed
  shellcheck -x "$ROOT/tests/"*.sh
fi

if [[ "$VERBOSE" = "1" ]]; then
  echo "lint OK (verbose)"
else
  echo "lint OK"
fi