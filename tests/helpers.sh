#!/usr/bin/env bash
red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

# run_case <name> <cmd...>
run_case() {
  local name="$1"
  shift
  local log="$BUILD_DIR/logs/$name.log"
  mkdir -p "$(dirname "$log")"

  {
    echo "== $name =="
    printf 'argv:'
    for a in "$@"; do printf ' [%s]' "$a"; done
    printf '\n'
  } > "$log"

  if "$@" >> "$log" 2>&1; then
    green "Case OK: $name"
  else
    red "Case FAILED: $name"
    echo "Case FAILED: $name" >> "$log"
    mkdir -p "$BUILD_DIR"
    echo "$name" >> "$BUILD_DIR/failed"
    return 1
  fi
}
