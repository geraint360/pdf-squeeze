#!/usr/bin/env bash
set -euo pipefail

# paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Controls:
#   VERBOSE=1 → show diffs, detailed output
#   FIX=0     → don't rewrite files (default: rewrite when possible)
VERBOSE="${VERBOSE:-0}"
FIX="${FIX:-1}"

# --- zsh syntax check (quiet unless error) ---
# Only if the zsh entrypoint exists.
if [[ -f "$ROOT/pdf-squeeze" ]]; then
  zsh -n "$ROOT/pdf-squeeze"
fi

# --- format bash test scripts (shfmt) ---
if command -v shfmt > /dev/null 2>&1; then
  # Collect test shell scripts robustly (handles 0 matches) — portable for Bash 3.2
  TEST_SH=()
  while IFS= read -r -d '' f; do
    TEST_SH+=("$f")
  done < <(find "$ROOT/tests" "$ROOT/scripts" -type f -name '*.sh' -print0 2> /dev/null || printf '\0')

  if [[ "${#TEST_SH[@]}" -gt 0 ]]; then
    if [[ "$FIX" = "1" ]]; then
      shfmt -w -i 2 -bn -ci -sr "${TEST_SH[@]}"
    else
      if [[ "$VERBOSE" = "1" ]]; then
        shfmt -d -i 2 -bn -ci -sr "${TEST_SH[@]}"
      else
        if shfmt -l -i 2 -bn -ci -sr "${TEST_SH[@]}" | grep . > /dev/null; then
          echo "shfmt: files need formatting (rerun with FIX=1 or VERBOSE=1 for details)"
          exit 1
        fi
      fi
    fi
  fi
fi

if [[ "$VERBOSE" = "1" ]]; then
  echo "lint OK (verbose)"
else
  echo "lint OK"
fi
