#!/usr/bin/env bash
set -euo pipefail

# pdf-squeeze one-shot installer for macOS
# - Installs Homebrew (if missing)
# - Installs dependencies (ghostscript, pdfcpu, qpdf, mupdf-tools, exiftool, poppler, coreutils, parallel*)
# - Installs pdf-squeeze to ~/bin (configurable via --prefix)
# - Installs DEVONthink scripts (compiled .scpt) for DT4 and DT3 if present
# - Supports: --no-parallel, --verify-only, --uninstall
#
# Usage:
#   bash install-pdf-squeeze.sh [--no-parallel] [--prefix ~/bin] [--verify-only] [--uninstall]
#
# Repo: https://github.com/geraint360/pdf-squeeze

REPO_RAW="https://raw.githubusercontent.com/geraint360/pdf-squeeze/main"
PREFIX_DEFAULT="$HOME/bin"
INSTALL_PREFIX="$PREFIX_DEFAULT"
INSTALL_PARALLEL=1
VERIFY_ONLY=0
UNINSTALL=0

log() { printf "%s\n" "$*" >&2; }
die() { log "Error: $*"; exit 1; }

usage() {
  cat >&2 <<EOF
Usage: $0 [options]

Options:
  --prefix PATH       Where to install pdf-squeeze (default: $PREFIX_DEFAULT)
  --no-parallel       Do not install GNU parallel
  --verify-only       Check installation status without making changes
  --uninstall         Remove installed files (does not remove Homebrew or brew packages)
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) shift; INSTALL_PREFIX="${1:-}"; [[ -n "${INSTALL_PREFIX}" ]] || die "--prefix needs a path";;
    --no-parallel) INSTALL_PARALLEL=0;;
    --verify-only) VERIFY_ONLY=1;;
    --uninstall) UNINSTALL=1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
  shift
done

on_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

ensure_macos() {
  on_macos || die "This installer is for macOS."
}

brew_path=""
have_brew() {
  if [[ -x /opt/homebrew/bin/brew ]]; then brew_path=/opt/homebrew/bin/brew; return 0; fi
  if [[ -x /usr/local/bin/brew ]]; then brew_path=/usr/local/bin/brew; return 0; fi
  return 1
}

eval_brew_shellenv() {
  if have_brew; then
    # shellcheck disable=SC2046
    eval "$($brew_path shellenv)"
  fi
}

install_homebrew_if_needed() {
  if have_brew; then
    eval_brew_shellenv
    return
  fi
  log "[brew] Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  have_brew || die "Homebrew installation appears to have failed."
  eval_brew_shellenv
}

brew_install_if_missing() {
  local pkg="$1"
  if ! brew list --formula --versions "$pkg" >/dev/null 2>&1; then
    log "[brew] Installing $pkg..."
    brew install "$pkg"
  else
    log "[brew] $pkg already installed."
  fi
}

ensure_dirs() {
  mkdir -p "$INSTALL_PREFIX"
  # Ensure ~/bin is on PATH if using default
  if [[ "$INSTALL_PREFIX" == "$HOME/bin" ]]; then
    if ! grep -q 'HOME/.*/bin' "${HOME}/.zprofile" 2>/dev/null && ! grep -q 'HOME/bin' "${HOME}/.zprofile" 2>/dev/null; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.zprofile"
      log "[path] Added ~/bin to ~/.zprofile"
    fi
  fi
}

download_to() {
  local url="$1" dst="$2"
  curl -fsSL "$url" -o "$dst"
}

install_files() {
  ensure_dirs

  # Install pdf-squeeze
  local bin_dst="$INSTALL_PREFIX/pdf-squeeze"
  log "[get] Installing pdf-squeeze -> $bin_dst"
  download_to "$REPO_RAW/pdf-squeeze" "$bin_dst"
  chmod +x "$bin_dst"

  # Install DEVONthink scripts (compiled .scpt from repo)
  local dt_menu="$HOME/Library/Application Scripts/com.devon-technologies.think/Menu"
  local dt_rules="$HOME/Library/Application Scripts/com.devon-technologies.think/Smart Rules"
  local dt3_menu="$HOME/Library/Application Scripts/com.devon-technologies.think3/Menu"
  local dt3_rules="$HOME/Library/Application Scripts/com.devon-technologies.think3/Smart Rules"
  mkdir -p "$dt_menu" "$dt_rules" "$dt3_menu" "$dt3_rules"

  log "[get] Installing DEVONthink scripts (.scpt)"
  download_to "$REPO_RAW/devonthink-scripts/compiled/Compress%20PDF%20Now.scpt" \
              "$dt_menu/Compress PDF Now.scpt"
  download_to "$REPO_RAW/devonthink-scripts/compiled/PDF%20Squeeze%20(Smart%20Rule).scpt" \
              "$dt_rules/PDF Squeeze (Smart Rule).scpt"

  # Also copy to DT3 if present (harmless if DT3 not installed)
  cp -f "$dt_menu/Compress PDF Now.scpt" "$dt3_menu/Compress PDF Now.scpt" 2>/dev/null || true
  cp -f "$dt_rules/PDF Squeeze (Smart Rule).scpt" "$dt3_rules/PDF Squeeze (Smart Rule).scpt" 2>/dev/null || true
}

install_deps() {
  install_homebrew_if_needed
  eval_brew_shellenv
  # Required deps
  local req=(ghostscript pdfcpu qpdf mupdf-tools exiftool poppler coreutils)
  for p in "${req[@]}"; do brew_install_if_missing "$p"; done
  # Optional
  if [[ $INSTALL_PARALLEL -eq 1 ]]; then brew_install_if_missing parallel; fi
}

uninstall_everything() {
  local removed=0
  local bin_dst="$INSTALL_PREFIX/pdf-squeeze"
  if [[ -f "$bin_dst" ]]; then rm -f "$bin_dst"; log "[rm] $bin_dst"; removed=1; fi

  local dt_menu="$HOME/Library/Application Scripts/com.devon-technologies.think/Menu/Compress PDF Now.scpt"
  local dt_rules="$HOME/Library/Application Scripts/com.devon-technologies.think/Smart Rules/PDF Squeeze (Smart Rule).scpt"
  local dt3_menu="$HOME/Library/Application Scripts/com.devon-technologies.think3/Menu/Compress PDF Now.scpt"
  local dt3_rules="$HOME/Library/Application Scripts/com.devon-technologies.think3/Smart Rules/PDF Squeeze (Smart Rule).scpt"

  for f in "$dt_menu" "$dt_rules" "$dt3_menu" "$dt3_rules"; do
    if [[ -f "$f" ]]; then rm -f "$f"; log "[rm] $f"; removed=1; fi
  done

  if [[ $removed -eq 0 ]]; then
    log "[uninstall] Nothing to remove."
  else
    log "[uninstall] Done. (Homebrew and packages were not removed.)"
  fi
}

verify_report() {
  echo "=== pdf-squeeze installation report ==="
  echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "Homebrew: $(brew --version 2>/dev/null | head -n1 || echo 'missing')"
  echo "pdf-squeeze: $(command -v pdf-squeeze || echo 'not on PATH')"
  echo "pdfcpu: $(command -v pdfcpu || echo 'missing')"
  echo "ghostscript(gs): $(command -v gs || echo 'missing')"
  echo "qpdf: $(command -v qpdf || echo 'missing')"
  echo "mutool: $(command -v mutool || echo 'missing')"
  echo "exiftool: $(command -v exiftool || echo 'missing')"
  echo "pdftotext: $(command -v pdftotext || echo 'missing')"
  echo "gstat: $(command -v gstat || echo 'missing (from coreutils)')"
  echo "parallel: $(command -v parallel || echo 'missing (optional)')"
  echo
  echo "DEVONthink scripts:"
  for f in \
    "$HOME/Library/Application Scripts/com.devon-technologies.think/Menu/Compress PDF Now.scpt" \
    "$HOME/Library/Application Scripts/com.devon-technologies.think/Smart Rules/PDF Squeeze (Smart Rule).scpt" \
    "$HOME/Library/Application Scripts/com.devon-technologies.think3/Menu/Compress PDF Now.scpt" \
    "$HOME/Library/Application Scripts/com.devon-technologies.think3/Smart Rules/PDF Squeeze (Smart Rule).scpt"
  do
    if [[ -f "$f" ]]; then echo "  OK  $f"; else echo "  MISSING  $f"; fi
  done
  echo
  echo "PREFIX: $INSTALL_PREFIX"
  if [[ ":$PATH:" == *":$INSTALL_PREFIX:"* ]]; then
    echo "PATH includes $INSTALL_PREFIX"
  else
    echo "PATH does NOT include $INSTALL_PREFIX (add to ~/.zprofile)"
  fi
}

main() {
  ensure_macos

  if [[ $UNINSTALL -eq 1 ]]; then
    uninstall_everything
    exit 0
  fi

  if [[ $VERIFY_ONLY -eq 1 ]]; then
    verify_report
    exit 0
  fi

  log "[install] Ensuring dependencies via Homebrew..."
  install_deps

  log "[install] Fetching files from $REPO_RAW ..."
  install_files

  log "[install] Verifying..."
  verify_report
  log "[install] Complete."
}

main "$@"
