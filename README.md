# pdf-squeeze

A fast PDF size reducer for macOS. Targets material file‑size savings while keeping documents readable and searchable. Ships as a single script (`pdf-squeeze`, uses **zsh**) with pragmatic defaults and safety rails.

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
- Integrations with DEVONthink 3 and 4


---

## Requirements

macOS (tested on Sonoma) with the following tools installed:

- Ghostscript (`gs`)
- pdfcpu
- qpdf (for encrypted‑PDF handling and tests)
- exiftool
- poppler
- coreutils
- mupdf-tools (will use mupdf if already installed)
- parallel (optional)

The quick installer will automatically install Homebrew and these dependencies. 

The script is **zsh**; macOS ships with zsh by default.

The pdf-squeeze script probably works in Linux but it hasn't been tested. 

---

## Installation

### Quick Installation
Enter this into Terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/geraint360/pdf-squeeze/main/scripts/install-pdf-squeeze.sh | bash
```
Re-running this should update with the latest version from the repo.

### Quick Uninstallation
Enter this into Terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/geraint360/pdf-squeeze/main/scripts/install-pdf-squeeze.sh --uninstall | bash
```

---

## Usage

```bash
pdf-squeeze [options] <file-or-dir>...
```

### Common Options

- `-p, --preset <name>`  
  One of `light`, `standard`, `extreme`, `lossless`, `archive`.  
  Tunes compression strength and quality trade-offs.

- `-o, --output <file>`  
  Explicit output file (single input only).  
  If omitted, uses default naming (`*_squeezed.pdf`).

- `--inplace`  
  Compress and overwrite the input file.  
  Preserves the **original modification timestamp** (within ~2min APFS tolerance).

- `--dry-run`  
  Analyse inputs only, print projected savings and sizes, **don’t write any files**.

- `--recurse`  
  When directories are given, process PDFs recursively.

- `--include <regex>`  
  Process only files whose full path matches the given regex.

- `--exclude <regex>`  
  Skip any files whose full path matches the given regex.

- `--jobs <N>`  
  Parallel workers for batch mode (default: number of CPU cores).

- `--min-gain <pct>`  
  Only replace a file if the compressed result is at least this much smaller.  
  If smaller savings, the original is kept.

- `--skip-if-smaller <SIZE>`  
  Skip inputs below this size threshold (e.g. `5MB`, `200k`).

- `--password <pw>`  
  Password for encrypted PDFs. Without this, encrypted files are **skipped** safely.

- `--quiet`  
  Suppress the usual “arrow” output line for each processed file.

- `--version`, `--help`  
  Show version or usage.

**Output naming:**  
If neither `-o` nor `--inplace` is used, results are written next to the input as: `*_squeezed.pdf`.


### Advanced Options

- `-q <N>`  
  Force JPEG quality (1–100).  
  Overrides preset defaults (useful for custom tuning).

- `--keep-metadata` *(default)*  
  Preserve document metadata.

- `--strip-metadata`  
  Remove all metadata for smaller output or privacy.

- `--keep-date` *(default)*  
  Preserve original timestamps (mtime/atime) when writing new files.

- `--no-keep-date`  
  Update file timestamps to the compression completion time.

- `--deterministic` *(default)*  
  Ensures **stable, reproducible output** for identical inputs and presets.  
  Useful for deduplication workflows.

- `--non-deterministic`  
  Allow compression libraries to vary slightly for speed at the cost of reproducibility.

- `--password-file <FILE>`  
  Provide a password for encrypted PDFs via a file (safer than inline `--password`).

- `--post-hook 'CMD {}'`  
  Run a shell command after successfully processing each file.  
  `{}` is replaced with the output path.  
  Example:  
  ```bash
  --post-hook 'echo Compressed: {} >> ~/processed.log'
  ```

-	`--sidecar-sha256`
  Generate a .sha256 checksum file alongside each output.
  Useful for integrity checks, deduplication, and DEVONthink integration.

- `--check-deps`
  Verify required and optional tool availability, then exit.

-	`--debug`
  Print computed parameters, selected DPI, JPEG quality, estimated savings, etc.
  Does not write files.

- `--log <FILE>`
  Append results to the specified log file in CSV format, including input/output size,
  savings, and status.

### Preset strength ordering

By design: `extreme ≤ standard ≤ light` in resulting size (within ~5%).  
`lossless` preserves quality/structure as much as possible; `archive` aims for highest compression that still prints well.

---

## Examples

**Super Basic**
```bash
# Compress using the default preset ("standard").
# Output will be written as input_squeezed.pdf next to the input,
# but only if the compressed file is meaningfully smaller.
pdf-squeeze input.pdf
```

**Basic Explicit Output**
```bash
# Compress using the "standard" preset and write to a specific path:
pdf-squeeze -p standard input.pdf -o output.pdf
```

**Estimate Only (Dry Run)**
```bash
# Show estimated size and savings without modifying the file:
pdf-squeeze --dry-run -p light input.pdf
# Output:
# DRY: input.pdf  est_savings≈42%  est_size≈1.2MB (from 2.1MB)
```

**In-Place Compression (Preserve Timestamp)**
```bash
# Overwrite the original file in-place, but only keep the result if
# the compressed version is at least 25% smaller.
pdf-squeeze -p extreme --inplace --min-gain 25 input.pdf
```

**Batch a Folder (Recursive, Parallel)**
```bash
# Recurse into ~/Documents/PDFs, compress all PDFs using the standard preset,
# include only those under "/Reports/", skip any in "/Drafts/",
# and process up to 4 files in parallel.
pdf-squeeze -p standard --recurse \
  --include '/Reports/' --exclude '/Drafts/' \
  --jobs 4 ~/Documents/PDFs
```

**Skip Tiny Files (<5 MB)**
```bash
# Skip any PDFs smaller than 5 MB entirely:
pdf-squeeze --skip-if-smaller 5MB my.pdf -o my_small.pdf
```

**Encrypted PDFs**
```bash
# Without a password, encrypted PDFs are skipped safely:
pdf-squeeze input_encrypted.pdf -o out.pdf

# Provide a password to actually compress encrypted PDFs:
pdf-squeeze --password mysecretpassword input_encrypted.pdf -o out.pdf

# Better than passing --password directly on the CLI:
pdf-squeeze --password-file ~/secrets/pdfpass.txt input_encrypted.pdf
```

**Dry-Run Entire Tree (Planning View)**
```bash
# Show estimated savings for all PDFs in a directory tree,
# without writing any files:
pdf-squeeze --dry-run --recurse ~/Scans
```

**Use a Post-Hook (Integration Example)**
```bash
# Run a custom command after processing each file:
pdf-squeeze --inplace --post-hook 'echo Processed: {} >> ~/processed.log' ~/Scans/file.pdf
```

---

## Integration notes

### Determinism
- `--deterministic` ensures bit-for-bit reproducibility for identical inputs when using the same preset and options.
- `--no-deterministic` can produce slightly smaller outputs at the cost of reproducibility (e.g. due to non-fixed object IDs or encoding order).

### Metadata & Dates
- By default, metadata and timestamps are preserved.
- Use `--strip-metadata` for privacy-sensitive distributions or archival workflows.
- Use `--keep-date` (default) to preserve access/modify times on output.
- Use `--no-keep-date` to refresh timestamps to the compression time — useful for workflows where “last modified” should reflect the recompression.

### Exit Status Codes

- **0** → Success (including “skipped” files)
- **1** → No PDFs after filtering
- **2** → Usage error or unreadable input
- **127** → Missing dependency or environment misconfiguration

### Security

- If `--password` or `--password-file` is provided, the decrypted data is stored in a **secure temporary file**; the original is never modified in place.
- No password caching is performed; passwords are never logged.
- No external network calls are made during compression.

### Performance

- Most processing time is spent in **Ghostscript**; presets directly influence runtime.
- Use `--jobs <N>` to enable parallel compression for batch workloads.
- For large PDFs, expect increased temporary storage usage — especially on SSDs — due to intermediary render stages.
- For highly parallel workloads, ensure you have sufficient available disk space and CPU cores.

---

## DEVONthink Integration

There are two AppleScripts provided:

1.	**Compress PDF Now** — a menu/toolbar action to compress the selected PDFs immediately.
2.	**PDF Squeeze (Smart Rule)** — a handler for DEVONthink Smart Rules to compress PDFs automatically when they meet certain conditions (e.g. added to a group, file size > X).

By default, both scripts use **pdf-squeeze** with the **standard** compression preset, but this can be changed by editing the AppleScript headers if you prefer a different preset.

### Installation

The **quick installer** automatically installs the AppleScripts into the correct **DEVONthink 4** directories: 

```bash 
(curl -fsSL https://raw.githubusercontent.com/geraint360/pdf-squeeze/main/install-pdf-squeeze.sh)
```
>Tip: Re-running the installer will **update** the scripts to the latest version automatically.

**For DEVONthink 3:**
The scripts are compatible but are installed into a different path:
``~/Library/Application Scripts/com.devon-technologies.think3/``
Use the `--prefix` option if you need to override defaults.

### Using the Scripts in DEVONthink

**Compress PDF Now**
- Open **Preferences → Scripts** and ensure the scripts folder is enabled.
- Add the script to the **Toolbar** via _View → Customize Toolbar_ or run it from the **Scripts** menu.

**PDF Squeeze (Smart Rule)**
- Create a **Smart Rule** (_Tools → New Smart Rule…_)
- Choose your conditions (e.g. Kind is PDF, Size > 300 KB, etc.).
- Under **Perform the following actions**, select **Apply Script…** and choose
**PDF Squeeze (Smart Rule)**.
- For unattended operation, use `--inplace --min-gain 1` for safety, or customise flags in the AppleScript source.

### More Guidance
- When used with DEVONthink scripts:
- Let DEVONthink complete OCR **before** compression (pdf-squeeze does **not** perform OCR).
- Smart Rules can safely run `--inplace mode`; timestamps are preserved unless overridden with --no-keep-date.

**Recommended Defaults**

| Workflow | Suggested Flags |
|----------|-----------------|
| Safe default | `--inplace --min-gain 1` |
| Scans & large PDFs | `-p standard --inplace --min-gain 3` |
| Archival & privacy | `-p archive --inplace --min-gain 1 --strip-metadata` |

---

# Troubleshooting

- **“No PDFs found.”**  
  Check your path/quotes; without `--recurse`, directories aren’t descended.

- **“SKIP (encrypted)”**  
  Supply a password: `--password '…'` or `--password-file path`.

- **“SKIP (below …)”** or **“kept-original(below-threshold-or-larger)”**  
  Either the output was not smaller, or it didn’t meet `--min-gain`.  
  Lower `--min-gain`, or try `-p extreme`.

- **Tiny savings on vector‑only PDFs**  
  Expected; there’s little to compress beyond structure.

- **File looks slightly soft**  
  Use `-p light`, or keep `standard` and raise quality (e.g., `-q 80`).

- **“Missing: ghostscript / pdfcpu / qpdf / mutool / poppler / exiftool”**  
  Run:  
  ```bash
  brew install ghostscript pdfcpu qpdf mupdf-tools poppler exiftool coreutils
  ```

- **In‑place timestamp drift**  
  APFS granularity can cause small drift; the tool keeps it within ~2 minutes.

- **Unexpected skips or errors**  
  Use `--debug` to see exactly what the tool intends (inputs, DPI choices, JPEG Q, estimated savings, etc.).

- **Checksum verification failed**  
  If using `--sidecar-sha256`, mismatches indicate content changes since last run.

- **DEVONthink automation not working**  
  Ensure the `.scpt` scripts are installed in:
  ```
  ~/Library/Application Scripts/com.devon-technologies.think/Menu
  ~/Library/Application Scripts/com.devon-technologies.think/Smart Rules
  ```
  Then restart DEVONthink. (Updates to the Smart Rule won't take effect without restarting DEVONthink.)

---

# Development

## Build and Install

```bash
make install-bin          # installs ./pdf-squeeze → ~/bin/pdf-squeeze (default)
```
Ensure `~/bin` is on your `PATH`. Override the target with:
```bash
make install-bin PREFIX=/some/other/bin
```

## DEVONthink Scripts (Optional)

If you want the accompanying DEVONthink automations:

```bash
make compile              # compiles .applescript → .scpt under devonthink-scripts/compiled
make install-dt           # installs compiled .scpt into DEVONthink’s “App Scripts” folder
# Or both:
make install              # = install-bin + install-dt
```

By default, installs go to DEVONthink 4 locations.  
If you are using DEVONthink 3, specify the version explicitly:

```bash
make install-dt DT_VER=3
```

Or manually move the compiled `.scpt` files into DEVONthink 3's scripts location:

```
~/Library/Application Scripts/com.devon-technologies.think3/
```

## Repository Layout

- `pdf-squeeze` — the zsh CLI
- `tests/` — fixtures, helpers, and the full test suite
- `scripts/` — `lint.sh`, `format.sh`
- `devonthink-scripts/` — optional AppleScripts and compiled `.scpt`

## Running Tests

**Smoke test** (quick check):
```bash
make smoke
```

**Full suite** (rebuild fixtures, then run all tests):
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
- Deterministic size ordering (`extreme ≤ standard ≤ light` within tolerance)
- CSV logging (conditionally tested when supported)

**Useful environment flags:**

- `PDF_SQUEEZE_SKIP_CLEAN=1 make test` — keep existing `tests/assets`/`tests/build`
- `PDF_SQUEEZE_TEST_JOBS=8 make test` — control parallelism in the test harness

## Linting & Formatting

```bash
make lint           # automatically apply shfmt & minor fixes
make lint VERBOSE=1 # show detailed output
make lint FIX=1     # report only
```

## Make Targets

```text
install-bin   # copy ./pdf-squeeze → ~/bin/pdf-squeeze (override PREFIX=...)
compile       # build AppleScripts → devonthink-scripts/compiled
install-dt    # install compiled scripts into DEVONthink App Scripts folder
install       # = install-bin + install-dt
smoke         # quick CLI sanity test
test          # full suite
clean         # remove build and generated assets
```

---

## License

MIT © 2025 Geraint Preston

