# pdf-squeeze

A fast, batteries‑included PDF size reducer for macOS. Targets *sane* file‑size savings while keeping documents readable and searchable. Ships as a single script (`pdf-squeeze`, uses **zsh**) with pragmatic defaults and safety rails.

> Typical savings for mixed documents are 20–70% depending on content and preset. See **Presets** and examples below.

---

## Features

- Simple CLI: `pdf-squeeze input.pdf -o output.pdf` (or compress in place with `--inplace`)
- Multiple presets tuned for different trade‑offs: **light**, **standard**, **extreme**, **lossless**, **archive**
- Batch processing (files or folders), recursion, include/exclude filters, and parallel jobs
- Dry‑run estimator with projected size and savings (no writes)
- Skip rules to avoid work on tiny files or when savings would be negligible
- Timestamp‑friendly: preserves mtime for in‑place operations (APFS granularity tolerated)
- Optional password handling for encrypted PDFs (`--password`); otherwise it will **skip or pass‑through** safely
- Deterministic behavior and stable output naming (`*_squeezed.pdf`), unless `-o`/`--inplace` is used
- CSV logging (if your build advertises `--csv`, the tests auto‑detect this)
- Post‑hook support for integrations (e.g., re-indexing), see **Integration notes**

---

## Requirements

macOS (tested on Sonoma) with the following tools installed:

- **Ghostscript** (`gs`)
- **pdfcpu**
- **qpdf** (for encrypted‑PDF handling and tests)

Install via Homebrew:

```bash
brew install ghostscript pdfcpu qpdf
```

The script is **zsh**; macOS ships with zsh by default.

---

## Installation

### Quick
```bash
make install-bin          # installs ./pdf-squeeze → ~/bin/pdf-squeeze (default)
```
Ensure `~/bin` is on your `PATH`. Override the target with:
```bash
make install-bin PREFIX=/some/other/bin
```

### DEVONthink scripts (optional)
If you want the accompanying DEVONthink automations:

```bash
make compile              # compiles .applescript → .scpt under devonthink-scripts/compiled
make install-dt           # installs compiled .scpt into DEVONthink’s “App Scripts” folder
# Or both:
make install              # = install-bin + install-dt
```

---

## Usage

```bash
pdf-squeeze [options] <file-or-dir>...
```

### Common options

- `-p, --preset <name>`: one of `light`, `standard`, `extreme`, `lossless`, `archive`
- `-o, --output <file>`: explicit output file (single input only)
- `--inplace`           : write back to the same path (mtime preserved within ~2m tolerance)
- `--dry-run`           : print an estimate only, no files written
- `--recurse`           : when given directories, walk them recursively
- `--include <regex>`   : process only paths matching the regex
- `--exclude <regex>`   : skip paths matching the regex
- `--jobs <N>`          : parallel workers for batch mode
- `--min-gain <pct>`    : only keep the compressed result if it’s at least this % smaller
- `--skip-if-smaller <SIZE>` : immediately skip inputs smaller than the given size (e.g. `5MB`, `200k`)
- `--password <pw>`     : password for encrypted PDFs; otherwise the tool will skip/keep original safely
- `--csv <file>`        : (if available) append a CSV row per processed input
- `--post-hook '<cmd>'` : run a command after each processed file; `{}` is replaced with output path
- `--quiet`             : suppress the usual “arrow” result line
- `--version`, `--help`

**Output naming:** if you don’t use `-o` or `--inplace`, results are written next to the input as `*_squeezed.pdf`.

### Preset strength ordering

By design: `extreme ≤ standard ≤ light` in resulting size (within ~5%).  
`lossless` preserves quality/structure as much as possible; `archive` aims for highest compression that still prints well.

---

## Examples

Basic:
```bash
pdf-squeeze -p standard input.pdf -o output.pdf
```

Estimate only:
```bash
pdf-squeeze --dry-run -p light input.pdf
# DRY: input.pdf  est_savings≈42%  est_size≈1.2MB (from 2.1MB)
```

In place (preserve mtime; only keep if ≥25% smaller):
```bash
pdf-squeeze -p extreme --inplace --min-gain 25 input.pdf
```

Batch a folder, recurse, include only paths under “/Reports/” and exclude “/Drafts/”, 4 workers:
```bash
pdf-squeeze -p standard --recurse \
  --include '/Reports/' --exclude '/Drafts/' \
  --jobs 4 ~/Documents/PDFs
```

Skip tiny files (<5MB) quickly:
```bash
pdf-squeeze --skip-if-smaller 5MB my.pdf -o my_small.pdf
```

Encrypted inputs:
```bash
# Without a password the tool will print SKIP or keep the original.
pdf-squeeze input_encrypted.pdf -o out.pdf

# Provide password to actually compress:
pdf-squeeze --password secret -p light input_encrypted.pdf -o out.pdf
```

CSV logging:
```bash
pdf-squeeze -p light --csv report.csv some/folder --jobs 2
```

Post‑hook:
```bash
pdf-squeeze --inplace --post-hook 'echo Processed: {} >> ~/squeeze.log' ~/Scans/file.pdf
```

Dry‑run a tree (planning view):
```bash
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

### Exit status

- `0` success (including “skipped” files)
- `1` no PDFs after filtering
- `2` usage or unreadable input error
- `127` missing dependency

### Security

- If `--password`/`--password-file` is provided, decryption is to a **temporary file** only; the original is never modified in place.
- No password caching, no external network calls.

### Performance

- The heavy work is in Ghostscript. Use `--jobs N` for multi-file workloads.
- SSD scratch space is used for temps; large scans may create sizeable intermediates.

---

## DEVONthink Integration

There are two AppleScripts:

1. **Compress PDF Now** — a menu/toolbar action to compress the selected PDFs.
2. **PDF Squeeze (Smart Rule)** — a handler for DEVONthink Smart Rules to compress PDFs that match conditions (e.g. added to a group, file size > X).

### Compile AppleScripts

A) Using the command line
```bash
# From the repo root
osacompile -l AppleScript \
  -o devonthink-scripts/compiled/Compress\ PDF\ Now.scpt \
  devonthink-scripts/src/Compress\ PDF\ Now.applescript

osacompile -l AppleScript \
  -o devonthink-scripts/compiled/PDF\ Squeeze\ (Smart\ Rule).scpt \
  devonthink-scripts/src/PDF\ Squeeze\ (Smart\ Rule).applescript
```

B) Using the provided Makefile
```bash
make compile
```

### Install into DEVONthink

#### DEVONthink 4
```bash
mkdir -p ~/Library/Application\ Scripts/com.devon-technologies.think
cp devonthink-scripts/compiled/*.scpt \
   ~/Library/Application\ Scripts/com.devon-technologies.think/
# Or:
make install-dt DT_VER=4
```

#### DEVONthink 3
```bash
mkdir -p ~/Library/Application\ Scripts/com.devon-technologies.think3
cp devonthink-scripts/compiled/*.scpt \
   ~/Library/Application\ Scripts/com.devon-technologies.think3/
# Or:
make install-dt DT_VER=3
```

### Using the scripts inside DEVONthink

**Compress PDF Now**
- Open Preferences → Scripts and ensure the scripts folder is enabled.
- Add the script to the Toolbar (View → Customize Toolbar) or run it from the Scripts menu.

**Smart Rule Handler**
- Create a Smart Rule (Tools → New Smart Rule…)
- Choose conditions (e.g. Kind is PDF, Size > 300 KB, etc.)
- Perform the following actions → choose Run Script… and select the compiled script.

### Suggested flags for DEVONthink

| Mode                          | Flags                                         |
|-------------------------------|-----------------------------------------------|
| Safe default                  | `--inplace --min-gain 1`                      |
| Tighter compression on scans  | `-p standard --inplace --min-gain 3`          |
| Archival w/ stripped metadata | `-p archive --inplace --min-gain 1 --strip-metadata` |

Edit the header variables inside `devonthink-scripts/src/*.applescript` to set your preferred defaults.

---

## Development

### Repo layout
- `pdf-squeeze` — the zsh CLI
- `tests/` — fixtures, helpers and the full test suite
- `scripts/` — `lint.sh`, `format.sh`
- `devonthink-scripts/` — optional AppleScripts and compiled `.scpt`

### Running tests

Smoke test (quick sanity):
```bash
make smoke
```

Full suite (rebuild fixtures, then run):
```bash
make test
```

The suite verifies:
- All presets run and produce files
- `--dry-run` estimate prints
- `-o` is respected
- `--inplace` preserves timestamps (with tolerance)
- Filters (`--include/--exclude`), recurse, jobs
- `--skip-if-smaller`
- `--min-gain`
- Encrypted PDFs: safe behavior without password, success with `--password`
- Default naming rule
- Deterministic size ordering (`extreme ≤ standard ≤ light` with tolerance)
- CSV logging (when supported; test is conditional)

Useful environment flags:
- `PDF_SQUEEZE_SKIP_CLEAN=1 make test` — keep existing `tests/assets`/`tests/build`
- `PDF_SQUEEZE_TEST_JOBS=8 make test` — cap/raise parallelism in test harness

### Lint & formatting

```bash
make lint           # report only
make lint VERBOSE=1 # show details
make lint FIX=1     # apply shfmt & autofix minor issues
```

### Make targets

```text
install-bin   # copy ./pdf-squeeze → ~/bin/pdf-squeeze (override PREFIX=...)
compile       # build AppleScripts → devonthink-scripts/compiled
install-dt    # install compiled scripts into DEVONthink App Scripts folder
install       # = install-bin + install-dt
smoke         # quick CLI sanity
test          # full suite
clean         # remove build and generated assets
```

---

## Troubleshooting

- **“No PDFs found.”**  
  Check your path/quotes; without `--recurse`, directories aren’t descended.
- **“SKIP (encrypted)”**  
  Supply a password: `--password '…'` or `--password-file path`.
- **“SKIP (below …)”** or **“kept-original(below-threshold-or-larger)”**  
  Either the output was not smaller, or it didn’t meet `--min-gain`. Lower `--min-gain`, or try `-p extreme`.
- **Tiny savings on vector‑only PDFs**  
  Expected; there’s little to compress beyond structure.
- **File looks slightly soft**  
  Use `-p light`, or keep `standard` and raise quality (e.g., `-q 80`).
- **“Missing: ghostscript / pdfcpu / qpdf”** — install via Homebrew.
- **In‑place timestamp drift** — APFS granularity can cause small drift; the tool keeps it within ~2 minutes.
- **CSV not found** — your build may not include `--csv` support; tests skip automatically when unavailable.
- Run with `--debug` to see exactly what the tool intends (inputs, DPI choices, JPEG Q, estimated savings).

---

## Uninstall / Update

Just remove or replace the single script:

```bash
rm -f ~/bin/pdf-squeeze
# …or overwrite with the new version and chmod +x
```

---

## Changelog (abridged)

- **2.2.0‑zsh**  
  - zsh‑native; fixed subshell array bug; robust argv hand‑off  
  - BSD‑awk compatible image analyser (header‑driven; correct x/y‑ppi)  
  - `--dry-run` prints preset, estimated savings %, and size range  
  - Safer decryption; no `qpdf --replace-input`  
  - zsh‑correct cleanup: `setopt localtraps; trap … EXIT`  
  - Filtering supports `--include`/`--exclude` (regex)  
  - Deterministic by default; metadata & dates kept by default

---

## License

MIT © 2025 Geraint Preston
