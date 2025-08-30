# pdf-squeeze Test Suite

## What it does
- Builds deterministic image assets (tiny base64 JPEG/PNG)
- Creates PDFs with controlled effective PPI using `pdfcpu img add`
- Verifies:
  - All presets run and produce files
  - `--dry-run` estimates print
  - `-o` is respected
  - `--inplace` preserves timestamps
  - Filters (`--include/--exclude`)
  - `--skip-if-smaller`
  - Encrypted PDFs (skip without password, succeed with `--password`)
  - Sidecars + CSV logging
  - Deterministic output sizes

## Requirements
Installed via Homebrew (same as the main tool):

`brew install ghostscript pdfcpu qpdf mupdf exiftool poppler coreutils`

## Run
From repo root:

```
chmod +x tests/*.sh
tests/run.sh
```

Fixtures are created under `tests/build/`.
	
