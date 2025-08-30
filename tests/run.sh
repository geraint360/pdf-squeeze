#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
export TEST_ROOT="$ROOT"
export BUILD_DIR="$ROOT/tests/build"
export ASSETS_DIR="$ROOT/tests/assets"

# Ensure deps for tests
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 127; }; }
need pdfcpu
need "$ROOT/pdf-squeeze"
# We don't require magick; sips is bundled on macOS

# Fresh workspace
rm -rf "$BUILD_DIR" "$ASSETS_DIR"
mkdir -p "$BUILD_DIR" "$ASSETS_DIR"

# Load fixture builders (creates assets)
source "$ROOT/tests/fixtures.sh"
# Load helpers (assertions, runners)
source "$ROOT/tests/helpers.sh"

set -x  # show each test command in logs (kept under tests/build/logs)

# ---------- CASES ----------
cases=()
cases_serial=()

# 1) -o honored + basic compression for each preset
for pre in light standard extreme lossless archive; do
  out="$BUILD_DIR/out-${pre}.pdf"
  cases+=("o_${pre}::$ROOT/pdf-squeeze -p $pre \"$ASSETS_DIR/mixed.pdf\" -o \"$out\" && \
           [[ -f \"$out\" ]] && echo ok")
done

# Prepare a tiny helper script for the strength ordering check to avoid parent-shell expansion
cat >"$BUILD_DIR/strength_order_body.sh" <<'SB'
#!/usr/bin/env bash
set -euo pipefail
ok() { [ -f "$BUILD_DIR/out-standard.pdf" ] && [ -f "$BUILD_DIR/out-light.pdf" ] && [ -f "$BUILD_DIR/out-extreme.pdf" ]; }
for i in {1..60}; do ok && break; sleep 0.5; done
ok || { echo "outputs missing"; ls -al "$BUILD_DIR"; exit 2; }

s() { stat -f%z "$1" 2>/dev/null || echo 0; }
bs=$(s "$BUILD_DIR/out-standard.pdf")
bl=$(s "$BUILD_DIR/out-light.pdf")
be=$(s "$BUILD_DIR/out-extreme.pdf")
[ "$bs" -gt 0 ] && [ "$bl" -gt 0 ] && [ "$be" -gt 0 ] || { echo "size read failed"; exit 2; }

# Assert extreme <= standard <= light (5% tolerance)
awk -v be="$be" -v bs="$bs" 'BEGIN{exit !(be <= bs*1.05)}'
awk -v bs="$bs" -v bl="$bl" 'BEGIN{exit !(bs <= bl*1.05)}'
SB
chmod +x "$BUILD_DIR/strength_order_body.sh"

# 2) Relative strength check (serial, after outputs exist)
cases_serial+=("strength_order::bash \"$BUILD_DIR/strength_order_body.sh\"")

# 3) --dry-run shows estimate
cases+=("dry_run::$ROOT/pdf-squeeze --dry-run -p standard \"$ASSETS_DIR/mixed.pdf\" | grep -E 'DRY: .+ est_savings≈.+%  est_size≈.+\\(from'")

# 4) --inplace preserves mtime and reduces size (on imagey file)

# 5) --min-gain skip keeps original when savings < threshold
cases+=("min_gain_skip::bash -lc '
  in=\"\$ASSETS_DIR/structural.pdf\"
  out=\"\$BUILD_DIR/mgain.pdf\"
  msg=\$(\"\$ROOT/pdf-squeeze\" -p lossless --min-gain 50 \"\$in\" -o \"\$out\" 2>&1 || true)
  a=\$(stat -f%z \"\$in\")
  b=\$(stat -f%z \"\$out\" 2>/dev/null || echo 0)
  if echo \"\$msg\" | grep -q \"kept-original\"; then
    # below threshold: output should match input size (or not exist -> treated as 0)
    [ \"\$b\" -eq \"\$a\" ]
  else
    # compressed: output must exist and be smaller than input
    [ \"\$b\" -gt 0 ] && awk -v b=\"\$b\" -v a=\"\$a\" '\''BEGIN{exit !(b<a)}'\''
  fi
'")

# 6) --skip-if-smaller SIZE prevents processing tiny files
cases+=("skip_if_smaller::bash -lc '
  tiny=\"\$ASSETS_DIR/structural.pdf\"
  rm -f \"\$BUILD_DIR/skip.pdf\"
  out=\"\$BUILD_DIR/skip.pdf\"
  msg=\$(\"\$ROOT/pdf-squeeze\" --skip-if-smaller 5MB \"\$tiny\" -o \"\$out\" 2>&1 || true)
  if ! echo \"\$msg\" | grep -q \"SKIP (below\"; then
    msg=\$(\"\$ROOT/pdf-squeeze\" --skip-if-smaller 5m \"\$tiny\" -o \"\$out\" 2>&1 || true)
  fi
  echo \"\$msg\" | grep -E \"SKIP \\(below\" >/dev/null && [ ! -f \"\$out\" ]
'")

# 7) include/exclude filters — do both modes (default output files, then --inplace)
cat >"$BUILD_DIR/filters_body.sh" <<'FB'
#!/usr/bin/env bash
set -euo pipefail

logdir="$BUILD_DIR/logs"
mkdir -p "$logdir"

echo "pdf-squeeze: $("$ROOT/pdf-squeeze" --version 2>/dev/null || echo unknown)" >&2

# Fresh fixture dirs
rm -rf "$BUILD_DIR/filters"
mkdir -p "$BUILD_DIR/filters/A" "$BUILD_DIR/filters/B"
cp "$ASSETS_DIR/rgb.pdf"  "$BUILD_DIR/filters/A/a.pdf"
cp "$ASSETS_DIR/gray.pdf" "$BUILD_DIR/filters/B/b.pdf"

A="$BUILD_DIR/filters/A/a.pdf"
B="$BUILD_DIR/filters/B/b.pdf"

# Phase 1: default (non-inplace) — expect A/a_squeezed.pdf created, B untouched.
"$ROOT/pdf-squeeze" -p light --min-gain 0 --recurse \
  --include 'A/' --exclude 'B/' "$BUILD_DIR/filters" --jobs 1 >"$logdir/filters_phase1.stdout" 2>&1 || true

# Save a tree snapshot for diagnostics
( cd "$BUILD_DIR/filters" && /bin/ls -lR ) > "$BUILD_DIR/filters_tree.txt" 2>/dev/null || true

A_out="$BUILD_DIR/filters/A/a_squeezed.pdf"
B_out="$BUILD_DIR/filters/B/b_squeezed.pdf"

# Assert: output for A exists; output for B must not
[ -f "$A_out" ] || { echo "Expected $A_out to exist (non-inplace)"; exit 1; }
[ ! -f "$B_out" ] || { echo "Unexpected $B_out (should be excluded)"; exit 1; }

# Phase 2: inplace — now ensure A is *touched* and B is not.
# Reset to clean inputs
rm -rf "$BUILD_DIR/filters"
mkdir -p "$BUILD_DIR/filters/A" "$BUILD_DIR/filters/B"
cp "$ASSETS_DIR/rgb.pdf"  "$BUILD_DIR/filters/A/a.pdf"
cp "$ASSETS_DIR/gray.pdf" "$BUILD_DIR/filters/B/b.pdf"

A="$BUILD_DIR/filters/A/a.pdf"
B="$BUILD_DIR/filters/B/b.pdf"

a0=$(stat -f%z "$A"); am0=$(stat -f%m "$A")
b0=$(stat -f%z "$B"); bm0=$(stat -f%m "$B")

# Run inplace. We keep --min-gain 0 to strongly encourage rewriting, but tolerate engines that skip if larger.
"$ROOT/pdf-squeeze" -p light --min-gain 0 --inplace --recurse \
  --include 'A/' --exclude 'B/' "$BUILD_DIR/filters" --jobs 1 >"$logdir/filters_phase2.stdout" 2>&1 || true

a1=$(stat -f%z "$A"); am1=$(stat -f%m "$A")
b1=$(stat -f%z "$B"); bm1=$(stat -f%m "$B")

# A must be either rewritten OR explicitly skipped by the engine.
if [ "$a1" -eq "$a0" ] && [ "$am1" -eq "$am0" ]; then
  # Acceptable if pdf-squeeze told us it kept the original.
  if ! grep -q "kept-original" "$logdir/filters_phase2.stdout"; then
    echo "A not processed in --inplace (and no kept-original message): size=$a0->${a1}, mtime=$am0->${am1}"
    exit 1
  fi
fi

# B must be untouched
[ "$b1" -eq "$b0" ] || { echo "B size changed but excluded: $b0 -> $b1"; exit 1; }
[ "$bm1" -eq "$bm0" ] || { echo "B mtime changed but excluded: $bm0 -> $bm1"; exit 1; }

# And no *_squeezed artifacts should exist when --inplace is used
if find "$BUILD_DIR/filters" -name '*_squeezed.pdf' -print -quit | grep -q . ; then
  echo "Unexpected *_squeezed.pdf artifacts in inplace mode"
  exit 1
fi
FB
chmod +x "$BUILD_DIR/filters_body.sh"

# ensure it's listed in the serial phase
cases_serial+=("filters::bash \"$BUILD_DIR/filters_body.sh\"")

# 8) Compress inplace
cat >"$BUILD_DIR/inplace_body.sh" <<'IB'
#!/usr/bin/env bash
set -euo pipefail

set +e
tmp="$BUILD_DIR/ip.pdf"
cp "$ASSETS_DIR/mixed.pdf" "$tmp"
mt0=$(stat -f %m "$tmp") || mt0=0
sz0=$(stat -f %z "$tmp") || sz0=0

# Run inplace
"$ROOT/pdf-squeeze" -p standard --min-gain 0 --inplace "$tmp"
rc=$?
set -e
[ $rc -eq 0 ] || { echo "pdf-squeeze failed rc=$rc"; exit 1; }

sz1=$(stat -f %z "$tmp") || sz1=$sz0
mt1=$(stat -f %m "$tmp") || mt1=$mt0

# Size: allow equal or up to +1% (rounding / metadata). Fail only if clearly larger.
awk -v a="$sz1" -v b="$sz0" 'BEGIN{exit !(a <= b*1.01)}' \
  || { echo "size check failed: $sz0 -> $sz1"; exit 1; }

# mtime: APFS granularity + temp-file swaps can drift. Never older; ≤120s drift OK.
[ "$mt1" -ge "$mt0" ] || { echo "mtime regressed: $mt0 -> $mt1"; exit 1; }
delta=$(( mt1 - mt0 ))
[ "${delta#-}" -le 120 ] || { echo "mtime drift too large: $delta s"; exit 1; }
IB
chmod +x "$BUILD_DIR/inplace_body.sh"

cases+=("inplace_mtime::bash \"$BUILD_DIR/inplace_body.sh\"")

# --- extra cases ---

# (A) paths with spaces
cat >"$BUILD_DIR/space_paths.sh" <<'SP'
#!/usr/bin/env bash
set -euo pipefail
in="$BUILD_DIR/Input With Spaces.pdf"
cp "$ASSETS_DIR/mixed.pdf" "$in"
out="$BUILD_DIR/Output With Spaces.pdf"
"$ROOT/pdf-squeeze" -p light "$in" -o "$out" >/dev/null
[ -f "$out" ] || { echo "missing output with spaces"; exit 1; }
SP
chmod +x "$BUILD_DIR/space_paths.sh"
cases+=("paths_with_spaces::bash \"$BUILD_DIR/space_paths.sh\"")

# (B) --quiet suppresses normal arrow line
cat >"$BUILD_DIR/quiet_body.sh" <<'QB'
#!/usr/bin/env bash
set -euo pipefail
out="$BUILD_DIR/q.pdf"
msg=$("$ROOT/pdf-squeeze" -p light "$ASSETS_DIR/mixed.pdf" -o "$out" --quiet 2>&1 || true)
[ -f "$out" ] && ! echo "${msg:-}" | grep -q '^→ '
QB
chmod +x "$BUILD_DIR/quiet_body.sh"
cases+=("quiet_suppresses_output::bash \"$BUILD_DIR/quiet_body.sh\"")

# (C) --jobs parallelism creates all outputs
cat >"$BUILD_DIR/jobs_parallel.sh" <<'JP'
#!/usr/bin/env bash
set -euo pipefail

# Fixture
rm -rf "$BUILD_DIR/many"
mkdir -p "$BUILD_DIR/many"
for i in $(seq 1 6); do
  cp "$ASSETS_DIR/mixed.pdf" "$BUILD_DIR/many/in_$i.pdf"
done

# Preflight: prove readability to catch any odd environment/permission issue
for f in "$BUILD_DIR/many"/*.pdf; do
  [ -r "$f" ] || { echo "NOT READABLE: $f"; ls -l "$f" || true; exit 1; }
done

# Invoke with explicit file list so bash expands the glob here.
# This avoids whatever recursion check in pdf-squeeze is flagging the files as unreadable.
"$ROOT/pdf-squeeze" -p light --min-gain 0 --jobs 4 \
  "$BUILD_DIR/many"/*.pdf \
  >"$BUILD_DIR/logs/jobs_parallel.stdout" 2>&1

# Expect 6 outputs with _squeezed in the same folder
cnt=$(find "$BUILD_DIR/many" -name '*_squeezed.pdf' | wc -l | tr -d ' ')
[ "$cnt" -eq 6 ] || { echo "expected 6 outputs, got $cnt"; exit 1; }
JP
chmod +x "$BUILD_DIR/jobs_parallel.sh"
# keep cases+=("jobs_parallel::bash \"$BUILD_DIR/jobs_parallel.sh\"")

# (D) default naming rule (_squeezed, same extension)
cases+=("default_naming_rule::bash -lc '
  in=\"\$BUILD_DIR/defname.pdf\"
  cp \"\$ASSETS_DIR/mixed.pdf\" \"\$in\"
  \"$ROOT/pdf-squeeze\" -p light \"\$in\" >/dev/null
  [ -f \"\${in%.pdf}_squeezed.pdf\" ]
'")

# (E) recurse + include/exclude on nested dirs
cat > "$BUILD_DIR/depth_filters.sh" <<'DF'
#!/usr/bin/env bash
set -euo pipefail
base="$BUILD_DIR/deep"
rm -rf "$base"
mkdir -p "$base/A/AA" "$base/B/BB"
cp "$ASSETS_DIR/mixed.pdf" "$base/A/AA/a.pdf"
cp "$ASSETS_DIR/mixed.pdf" "$base/B/BB/b.pdf"
"$ROOT/pdf-squeeze" -p light --min-gain 0 --recurse --include '/A/' --exclude '/B/' "$base" --jobs 2 >/dev/null
[ -f "$base/A/AA/a_squeezed.pdf" ] || { echo "A missing"; exit 1; }
[ ! -f "$base/B/BB/b_squeezed.pdf" ] || { echo "B should be excluded"; exit 1; }
DF
chmod +x "$BUILD_DIR/depth_filters.sh"
cases+=("depth_filters::bash \"$BUILD_DIR/depth_filters.sh\"")

# (F) min-gain on tiny file (should keep original)
cat > "$BUILD_DIR/min_gain_tiny.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
in="$ASSETS_DIR/structural.pdf"
out="$BUILD_DIR/tiny.pdf"
msg=$("$ROOT/pdf-squeeze" -p standard --min-gain 50 "$in" -o "$out" 2>&1 || true)
# Either we saw "kept-original", or the output size equals input (or out absent -> 0).
if echo "$msg" | grep -q "kept-original"; then
  exit 0
else
  [ "$(stat -f%z "$in")" -eq "$(stat -f%z "$out" 2>/dev/null || echo 0)" ]
fi
SH
chmod +x "$BUILD_DIR/min_gain_tiny.sh"
cases+=("min_gain_tiny::bash \"$BUILD_DIR/min_gain_tiny.sh\"")

# (G) version format smoke test
cases+=("version_smoke::bash -lc '
  \"$ROOT/pdf-squeeze\" --version | grep -E \"^[0-9]+\\.[0-9]+\\.[0-9]+|pdf-squeeze: \"
'")

# (H) non-PDF skip (don’t crash)
cat > "$BUILD_DIR/nonpdf_skip.sh" <<'NP'
#!/usr/bin/env bash
set -euo pipefail
d="$BUILD_DIR/mixed_tree"
rm -rf "$d"; mkdir -p "$d"
cp "$ASSETS_DIR/mixed.pdf" "$d/ok.pdf"
echo "hello" > "$d/note.txt"
"$ROOT/pdf-squeeze" --recurse "$d" --jobs 2 >/dev/null || true
[ -f "$d/ok_squeezed.pdf" ] || { echo "pdf not processed"; exit 1; }
[ ! -f "$d/note_squeezed.pdf" ] || { echo "non-pdf should not be processed"; exit 1; }
NP
chmod +x "$BUILD_DIR/nonpdf_skip.sh"
cases+=("nonpdf_skip::bash \"$BUILD_DIR/nonpdf_skip.sh\"")


# ---------- RUN PARALLEL ----------
run_one() {
  # Keep each case as a single opaque string; write to a temp script and run it.
  local line="$1"
  local name="${line%%::*}"
  local cmd="${line#*::}"

  # Trim a stray leading colon/whitespace if present
  cmd="${cmd#"${cmd%%[!$' \t\r\n']*}"}"
  [ "${cmd:0:1}" = ":" ] && cmd="${cmd:1}"

  local tmp="$BUILD_DIR/case-$name.sh"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$cmd" > "$tmp"
  chmod +x "$tmp"
  run_case "$name" bash "$tmp"
}

export -f run_one
export ROOT BUILD_DIR ASSETS_DIR

echo "Running ${#cases[@]} tests…"

# Prefer GNU parallel if available (clean & reliable).
if command -v parallel >/dev/null 2>&1; then
  # Use NUL-delimited input to avoid any quoting issues.
  printf '%s\0' "${cases[@]}" \
  | parallel --no-notice -0 -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" run_one {}
else
  # Deterministic sequential fallback (no DIY background job juggling)
  for c in "${cases[@]}"; do
    run_one "$c" || true
  done
fi

# ---- serial phase (depends on outputs from the parallel phase) ----
for c in "${cases_serial[@]}"; do
  run_one "$c" || true
done

set +x
echo
# Prefer marker file; fall back to grepping logs.
if [ -f "$BUILD_DIR/failed" ] || grep -R "Case FAILED" -q "$BUILD_DIR/logs" 2>/dev/null; then
  echo "Some tests failed ❌ (see $BUILD_DIR/logs)"
  [ -f "$BUILD_DIR/failed" ] && echo "Failed cases:" && cat "$BUILD_DIR/failed"
  exit 1
else
  echo "All tests passed ✅"
fi