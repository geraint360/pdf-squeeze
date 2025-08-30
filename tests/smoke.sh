#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 127; }; }

# Required CLIs
need ghostscript
need pdfcpu
[ -x "$ROOT/pdf-squeeze" ] || { echo "pdf-squeeze not found/executable at $ROOT/pdf-squeeze"; exit 1; }

# Version/Help don’t explode
"$ROOT/pdf-squeeze" --version >/dev/null
"$ROOT/pdf-squeeze" --help    >/dev/null

# Dry-run prints the estimate line
tmp="$ROOT/tests/assets-smoke"
rm -rf "$tmp"; mkdir -p "$tmp"
# Make a tiny 1-page fixture via pdfcpu so this also checks pdfcpu is sane
cat >"$tmp/one.json" <<JSON
{"pages":{"1":{"mediaBox":[0,0,612,792], "content": [{"text": {"fontName":"Helvetica","fontSize":14,"x":72,"y":720,"desc":"hello"}}]}}}
JSON
pdfcpu create "$tmp/one.json" "$tmp/one.pdf" >/dev/null

"$ROOT/pdf-squeeze" --dry-run -p light "$tmp/one.pdf" | grep -E 'DRY: .+ est_savings≈.+%  est_size≈.+\(from' >/dev/null
echo "smoke ok"
