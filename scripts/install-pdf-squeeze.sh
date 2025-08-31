#!/usr/bin/env bash
set -euo pipefail

# pdf-squeeze installer (macOS + Linux)
# - Installs Homebrew on macOS (if missing)
# - Installs deps (gs, pdfcpu, qpdf, exiftool, poppler, coreutils, mutool, parallel*)
# - Installs pdf-squeeze to ~/bin (override with --prefix)
# - Installs DEVONthink scripts on macOS (DT4/DT3) only when --with-devonthink is passed
# - Supports: --no-parallel, --verify-only, --uninstall
#
# Usage:
# curl -fsSL https://raw.githubusercontent.com/geraint360/pdf-squeeze/main/scripts/install-pdf-squeeze.sh | bash
#
REPO_RAW="https://raw.githubusercontent.com/geraint360/pdf-squeeze/main"
PDFCPU_VERSION="0.11.0"   # linux fallback download if no package is available

PREFIX_DEFAULT="$HOME/bin"
INSTALL_PREFIX="$PREFIX_DEFAULT"
INSTALL_PARALLEL=1
VERIFY_ONLY=0
UNINSTALL=0
INSTALL_DT=0              # macOS only (off by default)
DT_MODE="auto"            # Which DEVONthink to target on macOS: auto|3|4


log() { printf "%s\n" "$*" >&2; }
die() { log "Error: $*"; exit 1; }

usage() {
  cat >&2 <<EOF
Usage: $0 [options]

Options:
  --with-devonthink   Install DEVONthink scripts on macOS
  --dt {auto|3|4}     Target DEVONthink version on macOS (default: auto)
  --prefix PATH       Where to install pdf-squeeze (default: $PREFIX_DEFAULT)
  --no-parallel       Do not install GNU parallel
  --verify-only       Check installation status without making changes
  --uninstall         Remove installed files (does not remove system packages)
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) shift; INSTALL_PREFIX="${1:-}"; [[ -n "${INSTALL_PREFIX}" ]] || die "--prefix needs a path";;
    --with-devonthink) INSTALL_DT=1;;
		--dt) shift; DT_MODE="${1:-auto}"; case "$DT_MODE" in auto|3|4) ;; *) die "--dt must be auto|3|4";; esac ;;
    --no-parallel) INSTALL_PARALLEL=0;;
    --verify-only) VERIFY_ONLY=1;;
    --uninstall) UNINSTALL=1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
  shift
done

# Legacy shim (harmless if unused):
detect_dt_apps() { :; }

on_macos()  { [[ "$(uname -s)" == "Darwin" ]]; }
on_linux()  { [[ "$(uname -s)" == "Linux"  ]]; }

arch_id() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) echo "amd64" ;;  # default
  esac
}

# ---------- macOS (Homebrew) ----------
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
  if have_brew; then eval_brew_shellenv; return; fi
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
ensure_mutool_macos() {
  if command -v mutool >/dev/null 2>&1; then
    log "[deps] mutool OK ($(command -v mutool))"
    return 0
  fi
  # Try to link from mupdf or install mupdf-tools
  if brew list --versions mupdf >/dev/null 2>&1; then
    brew link mupdf >/dev/null 2>&1 || true
    if command -v mutool >/dev/null 2>&1; then log "[deps] mutool OK via mupdf"; return 0; fi
  fi
  log "[deps] installing mupdf-tools to provide mutool..."
  if ! brew install mupdf-tools; then
    log "[deps] Homebrew refused mupdf-tools (conflict with mupdf). Try: brew unlink mupdf && brew install mupdf-tools"
    return 1
  fi
  command -v mutool >/dev/null 2>&1 || die "mutool still not found after installing mupdf-tools"
}
install_deps_macos() {
  install_homebrew_if_needed
  eval_brew_shellenv
  local req=(ghostscript pdfcpu qpdf exiftool poppler coreutils)
  for p in "${req[@]}"; do brew_install_if_missing "$p"; done
  ensure_mutool_macos
  if [[ $INSTALL_PARALLEL -eq 1 ]]; then brew_install_if_missing parallel; fi
}

# ---------- Linux (apt/dnf/pacman/zypper) ----------
pkg_mgr=""
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then pkg_mgr="apt"
  elif command -v dnf      >/dev/null 2>&1; then pkg_mgr="dnf"
  elif command -v pacman   >/dev/null 2>&1; then pkg_mgr="pacman"
  elif command -v zypper   >/dev/null 2>&1; then pkg_mgr="zypper"
  else pkg_mgr=""
  fi
}
linux_install_pkgs() {
  # Arguments: packages...
  local pkgs=("$@")
  case "$pkg_mgr" in
    apt)
      sudo apt-get update -y
      sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
      ;;
    dnf)
      sudo dnf install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "${pkgs[@]}"
      ;;
    zypper)
      sudo zypper refresh
      sudo zypper install -y "${pkgs[@]}"
      ;;
    *)
      die "Unsupported Linux distro (no apt/dnf/pacman/zypper detected)."
      ;;
  esac
}
install_pdfcpu_linux_if_missing() {
  if command -v pdfcpu >/dev/null 2>&1; then
    log "[deps] pdfcpu already present ($(command -v pdfcpu))"
    return
  fi
  # Try package first (some distros package it)
  case "$pkg_mgr" in
    apt)    sudo apt-get install -y pdfcpu     || true ;;
    dnf)    sudo dnf install -y pdfcpu         || true ;;
    pacman) sudo pacman -S --noconfirm pdfcpu  || true ;;
    zypper) sudo zypper install -y pdfcpu      || true ;;
  esac
  if command -v pdfcpu >/dev/null 2>&1; then
    log "[deps] pdfcpu installed via package manager"
    return
  fi
  # Fallback: download prebuilt release (try a few common asset names)
  local arch; arch="$(arch_id)"
  local tmp dir url
  tmp="$(mktemp -d)"
  dir="$tmp/pdfcpu"
  mkdir -p "$dir"

  # Try candidates
  urls=(
    "https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_linux_${arch}.tar.xz"
    "https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_${arch}.tar.xz"
    "https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_$( [[ $arch == amd64 ]] && echo x86_64 || echo ${arch} ).tar.xz"
  )
  local ok=0
  for url in "${urls[@]}"; do
    log "[deps] Trying $url"
    if curl -fsSL "$url" -o "$tmp/pdfcpu.tar.xz"; then ok=1; break; fi
  done
  [[ $ok -eq 1 ]] || die "Failed to download pdfcpu tarball"

  tar -xJf "$tmp/pdfcpu.tar.xz" -C "$dir"
  if [[ -f "$dir/pdfcpu" ]]; then
    if [[ -w /usr/local/bin ]]; then
      sudo install -m 0755 "$dir/pdfcpu" /usr/local/bin/pdfcpu
      log "[deps] pdfcpu -> /usr/local/bin/pdfcpu"
    else
      mkdir -p "$HOME/bin"
      install -m 0755 "$dir/pdfcpu" "$HOME/bin/pdfcpu"
      log "[deps] pdfcpu -> $HOME/bin/pdfcpu (add \$HOME/bin to PATH if needed)"
    fi
  else
    die "pdfcpu binary not found in downloaded archive"
  fi
  rm -rf "$tmp"
}
install_deps_linux() {
  detect_pkg_mgr
  [[ -n "$pkg_mgr" ]] || die "Could not detect a supported package manager."

  # Map package names per distro
  local pkgs=()
  case "$pkg_mgr" in
    apt)
      pkgs=(ghostscript qpdf libimage-exiftool-perl poppler-utils coreutils mupdf-tools)
      ;;
    dnf)
      pkgs=(ghostscript qpdf perl-Image-ExifTool poppler-utils coreutils mupdf-tools)
      ;;
    pacman)
      pkgs=(ghostscript qpdf perl-image-exiftool poppler coreutils mupdf-tools)
      ;;
    zypper)
      pkgs=(ghostscript qpdf exiftool poppler-tools coreutils mupdf-tools)
      ;;
  esac
  if [[ $INSTALL_PARALLEL -eq 1 ]]; then pkgs+=(parallel); fi

  log "[install] Installing Linux dependencies via $pkg_mgr..."
  linux_install_pkgs "${pkgs[@]}"

  # Ensure mutool exists (mandatory). If the chosen package set didn't provide it, try 'mupdf'.
  if ! command -v mutool >/dev/null 2>&1; then
    log "[deps] mutool not found, trying 'mupdf' as a provider..."
    linux_install_pkgs mupdf || true
    command -v mutool >/dev/null 2>&1 || die "mutool not found (install 'mupdf-tools' or 'mupdf')."
  fi

  # Ensure pdfcpu exists (package or prebuilt release)
  install_pdfcpu_linux_if_missing
}

# ---------- DEVONthink installation ----------

# Echo the DEVONthink "Application Scripts" base dir(s) to target, one per line.
# Honors DT_MODE (auto|3|4). In auto mode, detect installed apps; if none found,
# default to both locations so the user can copy later if desired.
# Echo the DEVONthink "Application Scripts" base dir(s) to target, one per line.
# Honors DT_MODE (auto|3|4). In auto mode, detect installed apps; if none found,
# default to both locations so users can copy later if desired.
dt_target_dirs() {
  local want="${DT_MODE:-auto}"
  local d4="/Applications/DEVONthink 4.app"
  local d3="/Applications/DEVONthink 3.app"
  local base4="$HOME/Library/Application Scripts/com.devon-technologies.think"
  local base3="$HOME/Library/Application Scripts/com.devon-technologies.think3"

  case "$want" in
    4)
      [[ -d "$d4" ]] && printf '%s\n' "$base4"
      ;;
    3)
      [[ -d "$d3" ]] && printf '%s\n' "$base3"
      ;;
    auto|*)
      # Only emit directories for actually installed versions; no fallback.
      [[ -d "$d4" ]] && printf '%s\n' "$base4"
      [[ -d "$d3" ]] && printf '%s\n' "$base3"
      ;;
  esac
}
install_dt_scripts_macos() {
  local base_url="$REPO_RAW/devonthink-scripts/src"
  local src_menu_url="$base_url/Compress%20PDF%20Now.applescript"
  local src_rule_url="$base_url/PDF%20Squeeze%20(Smart%20Rule).applescript"

  local tmp_dir src_menu src_rule
  tmp_dir="$(mktemp -d)"
  src_menu="$tmp_dir/Compress PDF Now.applescript"
  src_rule="$tmp_dir/PDF Squeeze (Smart Rule).applescript"

  log "[get] Fetching AppleScript sources…"
  curl -fsSL -o "$src_menu" "$src_menu_url"
  curl -fsSL -o "$src_rule" "$src_rule_url"

  local had=0
  while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    had=1
    local menu_dir="$base/Menu"
    local rules_dir="$base/Smart Rules"
    mkdir -p "$menu_dir" "$rules_dir"

    /usr/bin/osacompile -o "$menu_dir/Compress PDF Now.scpt"         "$src_menu" \
      || { log "[get] ERROR: osacompile menu"; rm -rf "$tmp_dir"; return 1; }
    /usr/bin/osacompile -o "$rules_dir/PDF Squeeze (Smart Rule).scpt" "$src_rule" \
      || { log "[get] ERROR: osacompile smart rule"; rm -rf "$tmp_dir"; return 1; }

    log "[get] Installed DT scripts to:"
    log "  - $menu_dir/Compress PDF Now.scpt"
    log "  - $rules_dir/PDF Squeeze (Smart Rule).scpt"
  done < <(dt_target_dirs)

  rm -rf "$tmp_dir"
  if [[ $had -eq 0 ]]; then
    log "[get] DEVONthink not found (mode=$DT_MODE); skipped AppleScript install."
  fi
}

# ---------- Main Installer ----------

ensure_dirs() {
  mkdir -p "$INSTALL_PREFIX"
  if [[ "$INSTALL_PREFIX" == "$HOME/bin" ]]; then
    if ! grep -q 'HOME/bin' "${HOME}/.zprofile" 2>/dev/null; then
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
  local bin_dst="$INSTALL_PREFIX/pdf-squeeze"
  log "[get] Installing pdf-squeeze -> $bin_dst"
  download_to "$REPO_RAW/pdf-squeeze" "$bin_dst"
  chmod +x "$bin_dst"

  if on_macos && [[ $INSTALL_DT -eq 1 ]]; then
    install_dt_scripts_macos
  fi
}

uninstall_everything() {
  local removed=0
  local bin_dst="$INSTALL_PREFIX/pdf-squeeze"
  if [[ -f "$bin_dst" ]]; then rm -f "$bin_dst"; log "[rm] $bin_dst"; removed=1; fi

  if on_macos; then
    local removed_dt=0
    while IFS= read -r base; do
      [[ -n "$base" ]] || continue
      local dt_menu="$base/Menu/Compress PDF Now.scpt"
      local dt_rules="$base/Smart Rules/PDF Squeeze (Smart Rule).scpt"
      if [[ -f "$dt_menu" ]];  then rm -f "$dt_menu";  log "[rm] $dt_menu";  removed=1; removed_dt=1; fi
      if [[ -f "$dt_rules" ]]; then rm -f "$dt_rules"; log "[rm] $dt_rules"; removed=1; removed_dt=1; fi
    done < <(dt_target_dirs)
    [[ $removed_dt -eq 0 ]] && log "[uninstall] No matching DEVONthink paths (mode=$DT_MODE)."
  fi

  if [[ $removed -eq 0 ]]; then
    log "[uninstall] Nothing to remove."
  else
    log "[uninstall] Done. (System packages were not removed.)"
  fi
}

verify_report() {
  echo "=== pdf-squeeze installation report ==="
  echo "OS: $(uname -s) ($(uname -m))"
  echo "pdf-squeeze: $(command -v pdf-squeeze || echo 'not on PATH')"
  echo "ghostscript: $(command -v gs || echo 'missing')"
  echo "pdfcpu: $(command -v pdfcpu || echo 'missing')"
  echo "qpdf: $(command -v qpdf || echo 'missing')"
  echo "mutool: $(command -v mutool || echo 'missing')"
  echo "exiftool: $(command -v exiftool || echo 'missing')"
  echo "pdftotext: $(command -v pdftotext || echo 'missing')"
  echo "gstat: $(command -v gstat || echo 'missing (from coreutils)')"
  echo "parallel: $(command -v parallel || echo 'missing (optional)')"
  echo
	if on_macos; then
		# Only report DT status if user requested DT install OR scripts already exist.
		if [[ $INSTALL_DT -eq 1 ]]; then
			echo "DEVONthink scripts (mode=$DT_MODE):"
			local any=0
			while IFS= read -r base; do
				[[ -n "$base" ]] || continue
				any=1
				local menu="$base/Menu/Compress PDF Now.scpt"
				local rule="$base/Smart Rules/PDF Squeeze (Smart Rule).scpt"
				[[ -f "$menu" ]] && echo "  OK      $menu" || echo "  MISSING $menu"
				[[ -f "$rule" ]] && echo "  OK      $rule" || echo "  MISSING $rule"
			done < <(dt_target_dirs)
			[[ $any -eq 0 ]] && echo "  (no matching DEVONthink installation detected; nothing expected)"
		else
			# Check silently whether any DT scripts are present; if so, list them,
			# otherwise just say it was skipped.
			local any_exist=0
			while IFS= read -r base; do
				[[ -n "$base" ]] || continue
				for f in \
					"$base/Menu/Compress PDF Now.scpt" \
					"$base/Smart Rules/PDF Squeeze (Smart Rule).scpt"
				do
					[[ -f "$f" ]] && any_exist=1
				done
			done < <(dt_target_dirs)
	
			if [[ $any_exist -eq 1 ]]; then
				echo "DEVONthink scripts detected (mode=$DT_MODE):"
				while IFS= read -r base; do
					[[ -n "$base" ]] || continue
					local menu="$base/Menu/Compress PDF Now.scpt"
					local rule="$base/Smart Rules/PDF Squeeze (Smart Rule).scpt"
					[[ -f "$menu" ]] && echo "  OK      $menu" || true
					[[ -f "$rule" ]] && echo "  OK      $rule" || true
				done < <(dt_target_dirs)
			else
				echo "DEVONthink: (skipped; pass --with-devonthink to install)"
			fi
		fi
	else
		echo "DEVONthink: (not applicable on Linux)"
	fi
  echo
  echo "PREFIX: $INSTALL_PREFIX"
  if [[ ":$PATH:" == *":$INSTALL_PREFIX:"* ]]; then
    echo "PATH includes $INSTALL_PREFIX"
  else
    echo "PATH does NOT include $INSTALL_PREFIX (add to ~/.zprofile or your shell rc)"
  fi
}

main() {
  if [[ $UNINSTALL -eq 1 ]]; then
    uninstall_everything
    exit 0
  fi

  if [[ $VERIFY_ONLY -eq 1 ]]; then
    verify_report
    exit 0
  fi

  if on_macos; then
    log "[install] macOS detected"
    install_deps_macos
  elif on_linux; then
    log "[install] Linux detected"
    install_deps_linux
  else
    die "Unsupported OS: $(uname -s)"
  fi

  log "[install] Fetching files from $REPO_RAW ..."
  install_files

  log "[install] Verifying..."
  verify_report
  log "[install] Complete."
}

main "$@"