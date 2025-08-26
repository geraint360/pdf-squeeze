# `pdf-squeeze` — high-quality PDF compression for macOS (zsh, Apple Silicon)

World’s-best-without-OCR PDF compressor for the command line.  
Auto-tunes per file by analysing embedded images; preserves vector text and layout.  
Written for Apple Silicon; no Rosetta.

- zsh-native (no bashisms)
- Presets: **light**, **standard** (default), **extreme**, **lossless**, **archive**
- Batch, recurse, include/exclude filters, parallel workers
- In-place atomic replace or write to new file
- Metadata & timestamps preserved by default
- Deterministic IDs (stable output for the same input)
- Sidecar SHA-256, CSV logging, post-processing hook
- **No OCR** (by design; let DEVONthink or your OCR tool handle that)

Current script header: `version="2.2.0-zsh"`

---

## Installation

### 1) Dependencies (Homebrew)

```bash
brew install ghostscript pdfcpu qpdf mupdf exiftool poppler coreutils
# Optional (enables --jobs N parallelism):
brew install parallel
```

**Why each is needed**
- `ghostscript` — image downsampling/re-encoding, font subsetting
- `pdfcpu` — structural optimisation, final tidy/linearise
- `qpdf` — decryption (no in-place mutation), linearise fallback
- `mupdf` (`mutool`) — additional clean/deflate of resources
- `exiftool` — metadata strip (when requested)
- `poppler` (`pdfinfo`, `pdfimages`) — image/ppi analysis
- `coreutils` — `gstat`, `sha256sum` on macOS
- `parallel` — optional speed-up for many files

### 2) Script

Save the script as `~/bin/pdf-squeeze`, make it executable, and put `~/bin` on your PATH:

```bash
mkdir -p ~/bin
mv /path/to/pdf-squeeze ~/bin/pdf-squeeze
chmod +x ~/bin/pdf-squeeze

# Ensure ~/bin is on PATH (zsh):
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
exec zsh -l
```

### 3) Verify

```bash
pdf-squeeze --check-deps
pdf-squeeze --help
```

---

## Quick start

```bash
# Write "…_squeezed.pdf" next to the input
pdf-squeeze ~/Docs/Report.pdf

# In-place replacement (atomic), keep metadata & dates (default), skip tiny files
pdf-squeeze --inplace --skip-if-smaller 200KB ~/Scans/Invoice.pdf

# Recurse a folder, 6 workers, require ≥2% size reduction to replace
pdf-squeeze --recurse --jobs 6 --inplace --min-gain 2 ~/Scans

# See what would happen (preset + estimated saving & size range)
pdf-squeeze --dry-run ~/Scans/*.pdf

# Detailed reasoning without writing (DPI, JPEGQ, path, estimates)
pdf-squeeze --debug ~/Scans/Scan\ 002.pdf
```

---

## Presets (compression profiles)

| Preset     | Colour/Greyscale target | Mono (bilevel) | JPEG quality | Notes |
|------------|--------------------------|----------------|--------------|-------|
| `standard` | ~200–220 dpi (auto, ≥80% of file’s min PPI for safety) | ~900 dpi | ~74 | Balanced; default; keeps text crisp |
| `light`    | 300 dpi                  | 1200 dpi       | ~78          | Gentle size reduction |
| `extreme`  | 144 dpi                  | 600 dpi        | ~68          | Aggressive (closest to PDF Squeezer-style output) |
| `lossless` | no downsampling          | no downsampling| n/a          | Structural only (1–6% typical) |
| `archive`  | 240 dpi                  | 900 dpi        | ~74          | Deterministic + strip metadata |

**JPEG quality override:** `-q N` forces colour/grey JPEG Q (1–100) regardless of preset.

---

## Usage

```
pdf-squeeze [OPTIONS] INPUT...

INPUT may be one or more files and/or directories. Directories respect --recurse.
```

### Core options

- `-p {standard|light|extreme|lossless|archive}` — choose preset (default: `standard`)
- `--inplace` — replace original atomically (safe temp + move)
- `-o OUT` — write to a single output path (only valid when a single input file is given)
- `--recurse` — descend into subdirectories when an input is a directory
- `--jobs N` — process up to N files in parallel (requires `parallel`)

### Quality/heuristics

- `-q N` — force JPEG quality for colour/grey images (1–100), overriding preset
- `--min-gain PCT` — skip replace if saving is below PCT (default `1`)
- `--skip-if-smaller SIZE` — skip files smaller than SIZE  
  (SIZE accepts `K/KB`, `M/MB`, `G/GB`, e.g., `200KB`, `1.5MB`)

### Filtering (regex on full path)

- `--exclude REGEX` — skip matching paths (repeatable)
- `--include REGEX` — include only matching paths (repeatable). If any `--include` is supplied, non-matches are excluded.

### Metadata, timestamps, determinism

- `--keep-metadata` (default) | `--strip-metadata`
- `--keep-date` (default) | `--no-keep-date` — preserve atime/mtime on output
- `--deterministic` (default) | `--no-deterministic` — stable IDs for reproducible output

### Security (encrypted PDFs)

- `--password TEXT` | `--password-file FILE`  
  If the file is encrypted and a password is provided, it is **decrypted to a temp file** first (original not modified) and then processed.  
  If no password and the file is encrypted: the file is **skipped**.

### Dry-run / diagnostics / logging

- `--dry-run` — analyse only; print **preset, estimated savings %, and estimated size range**
- `--debug` — detailed analysis (ppi, counts, chosen DPI/JPEGQ/path, estimated %); no writes
- `--log CSV` — append CSV: `input_path,bytes_in,bytes_out,ratio,preset,note`
- `--sidecar-sha256` — write `input.pdf.pre.sha256` and `output.pdf.post.sha256`
- `--post-hook 'CMD {}'` — run a shell command per processed file; `{}` is replaced with output path.  
  Environment is populated: `IN`, `OUT`, `ORIG_BYTES`, `OUT_BYTES`, `PRESET`, `SAVEPCT`

### Other

- `--check-deps` — verify required/optional tools and exit
- `--quiet` — suppress normal “→ … (xx.x% smaller)” output
- `--help`, `--version`

---

## What the tool actually does (pipeline)

1. **Structural normalisation** (`pdfcpu optimize`) → fast size wins (1–6% typical)
2. **Image analysis** (`pdfimages -list`) → detect image count and **x/y PPI** per class:
   - colour (`rgb/cmyk/icc`)
   - grey
   - mono (bilevel; fallback using `bpc==1`)
3. **Preset selection & tuning**:
   - For `standard`, targets ~200–220 dpi but **never drops below 80% of the file’s minimum detected PPI** (to avoid blurring fine content).  
     JPEG quality defaults to ~74; lowered to 68 for very high-ppi originals.
4. **Image downsampling & re-encode** (`ghostscript`):
   - Colour/grey: DCT (JPEG)
   - Mono: JBIG2 **lossless** (`-dJBIG2Lossless=true`)
   - Fonts: subset + compress; pages not rotated; colour profiles left unchanged
5. **Final tidy**:
   - `pdfcpu optimize` (second pass)
   - `qpdf --linearize` (fast web view; best-effort)
   - `mutool clean -z` (deflate resources)
   - Optionally `exiftool -all=` to strip metadata
6. **Decision**:
   - Replace only if `bytes_out < bytes_in` **and** saving ≥ `--min-gain`
   - Preserve timestamps with `--keep-date`

---

## Estimation logic (`--dry-run` and `--debug`)

- Structural base win: 1–6%
- Image downsampling gain: approximated from `(target/median PPI)^2`, clipped, per class
- Mono (bilevel): JBIG2 **lossless** additional 10–60% typical (conservative midpoint added)
- Weighted by class counts
- Quality bonus: Q≤68 gives a few extra points
- Reported as a range (±30% around mid), but clamped to [3%, 90%]

Dry-run prints both **% range** and **estimated output size range**.

---

## Examples

```bash
# Match PDF Squeezer-ish behaviour on scans (aggressive)
pdf-squeeze -p extreme --inplace ~/Scans/*.pdf

# Conservative archive of research papers (strip metadata, deterministic)
pdf-squeeze -p archive --inplace ~/Papers

# Only process files ≥ 1.5 MB, skip any saving under 3%
pdf-squeeze --skip-if-smaller 1.5MB --min-gain 3 --inplace ~/Downloads

# Run a post-hook (e.g., re-index in DEVONthink or log somewhere)
pdf-squeeze --inplace --post-hook 'echo Processed: {} >> ~/squeeze.log' ~/Scans/file.pdf

# One-liner planning view (no changes)
pdf-squeeze --dry-run --recurse ~/Scans
```

---

## Integration notes

### DEVONthink
- Let DEVONthink perform OCR **before** compression (this script never OCRs).
- For background use on a server: schedule scans to a folder, then run `pdf-squeeze --recurse --inplace` on that folder via LaunchAgent or a cron-like tool.

### Determinism
- `--deterministic` yields stable object IDs; combined with fixed presets, outputs are reproducible for identical inputs.

### Metadata & dates
- Default is **keep**.  
  Use `--strip-metadata` for privacy-sensitive distributions.  
  `--keep-date` preserves access/modify times on output.

---

## Troubleshooting

- **“No PDFs found.”**  
  Check your path/quotes; without `--recurse`, directories aren’t descended.
- **“SKIP (encrypted)”**  
  Supply a password: `--password '…'` or `--password-file path`.
- **“SKIP (below …)”** or **“kept-original(below-threshold-or-larger)”**  
  Either the output was not smaller, or it didn’t meet `--min-gain`. Lower `--min-gain`, or try `-p extreme` / `-q 72`.
- **Tiny savings on vector-only PDFs**  
  Expected; there’s little to compress beyond structure.
- **File looks slightly soft**  
  Use `-p light`, or keep `standard` and raise `-q` (e.g., `-q 80`).  
  For scan-heavy docs, `standard` generally preserves small text; `extreme` is for when size matters more.

Run with `--debug` to see exactly what the tool intends (inputs, DPI choices, JPEG Q, estimated savings).

---

## Exit status

- `0` success (including “skipped” files)
- `1` no PDFs after filtering
- `2` usage or unreadable input error
- `127` missing dependency

---

## Security

- If `--password`/`--password-file` is provided, decryption is to a **temporary file** only; the original is never modified in place.
- No password caching, no external network calls.

---

## Performance

- The heavy work is in Ghostscript. Use `--jobs N` (with `parallel` installed) for multi-file workloads.
- SSD scratch space is used for temps; large scans may create sizeable intermediates.

---

## Uninstall / Update

Just remove or replace the single script:

```bash
rm -f ~/bin/pdf-squeeze
# …or overwrite with the new version and chmod +x
```

---

## License

You own your script; this README is provided to document its operation and usage.

---

### Changelog (abridged)

- **2.2.0-zsh**  
  - zsh-native; fixed subshell array bug; robust argv hand-off  
  - BSD-awk compatible image analyser (header-driven; correct x/y-ppi)  
  - `--dry-run` prints preset, estimated savings %, and size range  
  - Safer decryption: no `qpdf --replace-input`  
  - zsh-correct cleanup: `setopt localtraps; trap … EXIT`  
  - Filtering supports `--include`/`--exclude` (regex)  
  - Deterministic by default; metadata & dates kept by default
