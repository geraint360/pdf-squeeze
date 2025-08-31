#!/usr/bin/env bash
set -euo pipefail

# pdf-squeeze installer for macOS
# - Installs Homebrew (if missing) and adds shellenv to ~/.zprofile
# - Installs deps (ghostscript, pdfcpu, qpdf, exiftool, poppler, coreutils)
# - Tries to provide mutool (mupdf-tools preferred). If mupdf is installed and
#   conflicts, we WARN (optional dependency) instead of aborting.
# - Optionally installs parallel (unless --no-parallel)
# - Installs ~/bin/pdf-squeeze from GitHub (idempotent)
# - Compiles & installs DEVONthink scripts (.scpt) from repo sources
# - Flags: --no-parallel  --verify-only  --uninstall  --prefix PATH

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
  --verify-only       Check installation status (exits non-zero if missing reqs)
  --uninstall         Remove installed files (does not remove Homebrew or brew pkgs)
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

on_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
ensure_macos() { on_macos || die "This installer is for macOS."; }

brew_path=""
have_brew() {
  # Prefer explicit locations but fall back to PATH
  if [[ -x /opt/homebrew/bin/brew ]]; then brew_path=/opt/homebrew/bin/brew; return 0; fi
  if [[ -x /usr/local/bin/brew ]]; then brew_path=/usr/local/bin/brew; return 0; fi
  if command -v brew >/dev/null 2>&1; then brew_path="$(command -v brew)"; return 0; fi
  return 1
}

eval_brew_shellenv() {
  if have_brew; then
    eval "$("$brew_path" shellenv)"
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

  # Make sure future shells pick it up
  if [[ -x /opt/homebrew/bin/brew ]]; then
    grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
      { echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"; log "[brew] Added shellenv to ~/.zprofile"; }
  elif [[ -x /usr/local/bin/brew ]]; then
    grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || \
      { echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/.zprofile"; log "[brew] Added shellenv to ~/.zprofile"; }
  fi
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
    # Only add if not already present (anchored check)
    if ! grep -qE '(^|:)\$?HOME/bin(:|$)' "$HOME/.zprofile" 2>/dev/null; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zprofile"
      log "[path] Added ~/bin to ~/.zprofile"
    fi
  fi
}

download_to() {
  local url="$1" dst="$2"
  curl -fsSL "$url" -o "$dst"
}

install_dt_scripts() {
  log "[get] Installing DEVONthink scripts (.scpt)"
  local base="$HOME/Library/Application Scripts/com.devon-technologies.think"
  local menu_dir="$base/Menu"
  local rules_dir="$base/Smart Rules"
  mkdir -p "$menu_dir" "$rules_dir"

  local base_url="$REPO_RAW/devonthink-scripts/src"
  local src_menu_url="$base_url/Compress%20PDF%20Now.applescript"
  local src_rule_url="$base_url/PDF%20Squeeze%20(Smart%20Rule).applescript"

  local tmp_dir; tmp_dir="$(mktemp -d)"
  local src_menu="$tmp_dir/Compress PDF Now.applescript"
  local src_rule="$tmp_dir/PDF Squeeze (Smart Rule).applescript"

  curl -fsSL -o "$src_menu" "$src_menu_url" || { log "[get] ERROR: fetching Compress PDF Now.applescript"; rm -rf "$tmp_dir"; return 1; }
  curl -fsSL -o "$src_rule" "$src_rule_url" || { log "[get] ERROR: fetching PDF Squeeze (Smart Rule).applescript"; rm -rf "$tmp_dir"; return 1; }

  /usr/bin/osacompile -o "$menu_dir/Compress PDF Now.scpt"         "$src_menu" || { log "[get] ERROR: osacompile menu script"; rm -rf "$tmp_dir"; return 1; }
  /usr/bin/osacompile -o "$rules_dir/PDF Squeeze (Smart Rule).scpt" "$src_rule" || { log "[get] ERROR: osacompile smart rule"; rm -rf "$tmp_dir"; return 1; }

  rm -rf "$tmp_dir"
  log "[get] Installed:"
  log "  - $menu_dir/Compress PDF Now.scpt"
  log "  - $rules_dir/PDF Squeeze (Smart Rule).scpt"
}

# mutool is helpful but not always necessary; avoid failing the whole run if it conflicts
ensure_mutool_soft() {
  if command -v mutool >/dev/null 2>&1; then
    log "[deps] mutool OK ($(command -v mutool))"
    return 0
  fi

  # If mupdf-tools is present, mutool should exist
  if brew list --versions mupdf-tools >/dev/null 2>&1; then
    brew link --overwrite mupdf-tools >/dev/null 2>&1 || true
    if command -v mutool >/dev/null 2>&1; then
      log "[deps] mutool OK via mupdf-tools"
      return 0
    fi
  fi

  # Try installing mupdf-tools if mupdf is NOT installed
  if ! brew list --versions mupdf >/dev/null 2>&1; then
    log "[deps] Installing mupdf-tools to provide mutool..."
    if brew install mupdf-tools; then
      if command -v mutool >/dev/null 2>&1; then
        log "[deps] mutool OK via mupdf-tools"
        return 0
      fi
    fi
  fi

  # If we’re here, either mupdf is installed and conflicts, or install failed.
  if brew list --versions mupdf >/dev/null 2>&1; then
    log "[deps] WARNING: 'mupdf' is installed. If 'mutool' is needed, run:"
    log "        brew unlink mupdf && brew install mupdf-tools"
  else
    log "[deps] WARNING: 'mutool' not available (optional)."
  fi
  return 0
}

install_files() {
  ensure_dirs

  # Install pdf-squeeze
  local bin_dst="$INSTALL_PREFIX/pdf-squeeze"
  log "[get] Installing pdf-squeeze -> $bin_dst"
  download_to "$REPO_RAW/pdf-squeeze" "$bin_dst"
  chmod +x "$bin_dst"

  # Install DEVONthink scripts
  install_dt_scripts || true
}

install_deps() {
  install_homebrew_if_needed
  eval_brew_shellenv
  local req=(ghostscript pdfcpu qpdf exiftool poppler coreutils)
  for p in "${req[@]}"; do brew_install_if_missing "$p"; done
  ensure_mutool_soft
  if [[ $INSTALL_PARALLEL -eq 1 ]]; then brew_install_if_missing parallel; fi
}

verify_report() {
  local missing=0
  echo "=== pdf-squeeze installation report ==="
  echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "Homebrew: $(brew --version 2>/dev/null | head -n1 || echo 'missing')"
  printf "pdf-squeeze: "
  if command -v pdf-squeeze >/dev/null 2>&1; then
    echo "$(command -v pdf-squeeze)"
  else
    echo "not on PATH"; missing=1
  fi
  for tool in pdfcpu gs qpdf exiftool pdftotext gstat; do
    printf "%s: " "$tool"
    if command -v "$tool" >/dev/null 2>&1; then
      echo "$(command -v "$tool")"
    else
      echo "missing"; [[ "$tool" =~ ^(pdfcpu|gs|qpdf|pdftotext|gstat)$ ]] && missing=1
    fi
  done
  # Optional tools
  printf "mutool: "; command -v mutool >/dev/null 2>&1 && echo "$(command -v mutool)" || echo "missing (optional)"
  printf "parallel: "; command -v parallel >/dev/null 2>&1 && echo "$(command -v parallel)" || echo "missing (optional)"

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

  return $missing
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

main() {
  ensure_macos

  if [[ $UNINSTALL -eq 1 ]]; then
    uninstall_everything
    exit 0
  fi

  if [[ $VERIFY_ONLY -eq 1 ]]; then
    verify_report || exit 1
    exit 0
  fi

  log "[install] Ensuring dependencies via Homebrew..."
  install_deps

  log "[install] Fetching files from $REPO_RAW ..."
  install_files

  log "[install] Verifying..."
  if verify_report; then
    log "[install] Complete."
  else
    die "Verification failed (see report above)."
  fi
}

main "$@"