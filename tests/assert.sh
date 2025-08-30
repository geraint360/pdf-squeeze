#!/usr/bin/env bash
set -euo pipefail

RED=$'\e[31m'
GRN=$'\e[32m'
YLW=$'\e[33m'
RST=$'\e[0m'

pass() { printf "%s✓%s %s\n" "$GRN" "$RST" "$*"; }
fail() {
  printf "%s✗%s %s\n" "$RED" "$RST" "$*" >&2
  exit 1
}

# assert file exists
assert_file() {
  [[ -f "$1" ]] || fail "Expected file not found: $1"
  pass "File exists: $1"
}

# assert substring in output
assert_in() {
  printf "%s" "$1" | grep -q -- "$2" || fail "Expected to find '$2' in output"
  pass "Saw '$2' in output"
}

# assert bytes(a) < bytes(b) * (1 - min_saving)
# usage: assert_smaller OUT IN 0.10   # at least 10% smaller
assert_smaller() {
  local out="$1" in="$2" min="$3"
  local bo=$(stat -f%z "$out") bi=$(stat -f%z "$in")
  [[ "$bo" -lt $(awk -v b="$bi" -v m="$min" 'BEGIN{printf "%.0f", b*(1-m)}') ]] \
    || fail "Expected $out smaller than $in by >= $(awk -v m="$min" 'BEGIN{printf "%.0f%%",100*m}') (got $(awk -v a="$bo" -v b="$bi" 'BEGIN{printf "%.1f%%",100*(1-a/b)}'))"
  pass "$(basename "$out") is smaller than input by >= $(awk -v m="$min" 'BEGIN{printf "%.0f%%",100*m}')"
}

# assert timestamps equal (mtime only)
assert_same_mtime() {
  local a="$1" b="$2"
  local ma=$(stat -f%m "$a") mb=$(stat -f%m "$b")
  [[ "$ma" -eq "$mb" ]] || fail "mtime differs ($a: $ma, $b: $mb)"
  pass "mtime preserved"
}
