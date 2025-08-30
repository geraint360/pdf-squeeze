#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Ensure Homebrew bins are visible for non-login shells
if command -v brew >/dev/null 2>&1; then
  eval "$(/usr/bin/env brew shellenv)" 2>/dev/null || true
fi
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 127; }; }
need_any() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 && return 0; done; echo "Missing: $1"; exit 127; }

# Requirements
need_any gs ghostscript     # brew installs `gs`
need pdfcpu
[ -x "$ROOT/pdf-squeeze" ] || { echo "pdf-squeeze not found/executable at $ROOT/pdf-squeeze"; exit 1; }

# Version/Help should not error
"$ROOT/pdf-squeeze" --version >/dev/null || { echo "version failed"; exit 2; }
"$ROOT/pdf-squeeze" --help >/dev/null 2>&1 || true

# Make a tiny 1-page PDF with Ghostscript
tmp="$ROOT/tests/assets-smoke"
rm -rf "$tmp"; mkdir -p "$tmp"
gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite \
  -sOutputFile="$tmp/one.pdf" \
  -c "<</PageSize [612 792]>> setpagedevice /Helvetica findfont 14 scalefont setfont 72 720 moveto (hello) show showpage" >/dev/null

# Run a dry-run and validate it at least prints a DRY line.
# Capture stderr because pdf-squeeze writes the summary there.
out="$("$ROOT/pdf-squeeze" --dry-run -p light "$tmp/one.pdf" 2>&1 || true)"

# Be tolerant: only require a line that starts with "DRY:" (ignore the rest).
# Also fail fast if it looks like it skipped the file as unreadable.
if printf '%s\n' "$out" | LC_ALL=C grep -qi 'SKIP (unreadable'; then
  printf 'Unexpected dry-run output (unreadable skip):\n%s\n' "$out" >&2
  exit 2
fi

if ! printf '%s\n' "$out" | LC_ALL=C grep -q '^DRY:'; then
  printf 'Unexpected dry-run output (no DRY line):\n%s\n' "$out" >&2
  exit 2
fi

echo "smoke ok"