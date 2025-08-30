#!/usr/bin/env bash
set -euo pipefail

# Where to stage generated files
TEST_ROOT="${TEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$TEST_ROOT/tests/build}"
ASSETS_DIR="${ASSETS_DIR:-$TEST_ROOT/tests/assets}"

mkdir -p "$BUILD_DIR" "$ASSETS_DIR"

# Create a blank single-page PDF of given point size (pt)
# out: path to PDF to write
mkpdf_blank() {
  local ptw="$1" pth="$2" out="$3"
  # Require Ghostscript
  if ! command -v gs > /dev/null 2>&1; then
    echo "ERROR: Ghostscript (gs) not found; please install it (e.g. brew install ghostscript)" >&2
    exit 1
  fi
  # Create a truly blank, single-page PDF of the requested size in points
  gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite \
    -sOutputFile="$out" \
    -c "<</PageSize [$ptw $pth]>> setpagedevice showpage" > /dev/null
}

# Create a single-page PDF from an image, sized to a page of ptw x pth (points).
# Tries ImageMagick first; otherwise uses sips -> pdf, then Ghostscript to size/fit page.
mkpdf_img() {
  local img="$1" ptw="$2" pth="$3" out="$4"

  if command -v magick > /dev/null 2>&1; then
    # Density maps pixels to points (72pt/in, 144=>2x). Force the page box & fill.
    magick "$img" -units PixelsPerInch -density 144 \
      -resize "${ptw}x${pth}!" -page "${ptw}x${pth}" \
      -compress JPEG -quality 85 \
      "$out"
  else
    # Fallback: sips -> temp PDF, then Ghostscript to fix page size & fit
    local tmpPDF="${out%.pdf}.tmp.sips.pdf"
    /usr/bin/sips -s format pdf "$img" --out "$tmpPDF" > /dev/null
    gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite \
      -dDEVICEWIDTHPOINTS="$ptw" -dDEVICEHEIGHTPOINTS="$pth" \
      -dFIXEDMEDIA -dPDFFitPage \
      -sOutputFile="$out" "$tmpPDF" > /dev/null
    rm -f "$tmpPDF"
  fi
}

# Use macOS `sips` to generate images. If ImageMagick is present we’ll prefer `magick`.
_have() { command -v "$1" > /dev/null 2>&1; }

mkimg_rgb() {
  local w="$1" h="$2" out="$3"
  if _have magick; then
    magick -size "${w}x${h}" gradient:orange-blue "$out"
  else
    # sips can’t make gradients; we build a solid RGB then annotate to add entropy
    local tmp="$out.tmp.jpg"
    /usr/bin/sips -s format jpeg --resampleWidth "$w" --resampleHeight "$h" /System/Library/CoreServices/DefaultDesktop.jpg --out "$tmp" > /dev/null
    mv "$tmp" "$out"
  fi
}

mkimg_gray() {
  local w="$1" h="$2" out="$3"
  if _have magick; then
    magick -size "${w}x${h}" gradient:gray50-gray90 -colorspace Gray "$out"
  else
    local tmp="$out.tmp.jpg"
    /usr/bin/sips -s format jpeg --resampleWidth "$w" --resampleHeight "$h" -s formatOptions best --setProperty formatOptions best /System/Library/CoreServices/DefaultDesktop.jpg --out "$tmp" > /dev/null
    /usr/bin/sips -s format jpeg -s formatOptions best -s formatOptions best -s profile /System/Library/ColorSync/Profiles/Generic\ Gray\ Profile.icc "$tmp" --out "$out" > /dev/null 2>&1 || mv "$tmp" "$out"
    rm -f "$tmp" 2> /dev/null || true
  fi
}

mkimg_mono() {
  local w="$1" h="$2" out="$3"
  if _have magick; then
    magick -size "${w}x${h}" xc:white -fill black -draw "rectangle 0,0 $((w / 2)),$((h / 2))" -monochrome "$out"
  else
    # sips can’t do true 1bpp; approximate with hi-contrast JPEG
    local tmp="$out.tmp.jpg"
    /usr/bin/sips -s format jpeg --resampleWidth "$w" --resampleHeight "$h" /System/Library/CoreServices/DefaultDesktop.jpg --out "$tmp" > /dev/null
    mv "$tmp" "$out"
  fi
}

create_fixtures() {
  # Images
  mkimg_rgb 2400 3200 "$ASSETS_DIR/rgb.jpg" # ~300dpi @ 8"x10.6"
  mkimg_gray 2400 3200 "$ASSETS_DIR/gray.jpg"
  mkimg_mono 2550 3300 "$ASSETS_DIR/mono.jpg" # ~300dpi A4-ish

  # Single-page PDFs from images
  mkpdf_img "$ASSETS_DIR/rgb.jpg" 612 792 "$ASSETS_DIR/rgb.pdf" # US Letter 72pt/in
  mkpdf_img "$ASSETS_DIR/gray.jpg" 612 792 "$ASSETS_DIR/gray.pdf"
  mkpdf_img "$ASSETS_DIR/mono.jpg" 595 842 "$ASSETS_DIR/mono.pdf" # A4 72pt/in

  # Mixed, multi-page PDF (no pdfcpu subcommands needed)
  # Order: mono, gray, rgb (or whatever you want)
  gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite \
    -sOutputFile="$ASSETS_DIR/mixed.pdf" \
    "$ASSETS_DIR/mono.pdf" "$ASSETS_DIR/gray.pdf" "$ASSETS_DIR/rgb.pdf" > /dev/null

  # Small structural PDF (almost no images)
  mkpdf_blank 400 400 "$ASSETS_DIR/structural.pdf"
}

create_fixtures
