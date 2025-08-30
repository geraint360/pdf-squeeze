# pdf-squeeze – Test Suite

This directory contains a self-validating test harness for `pdf-squeeze`.  
It builds deterministic fixtures, runs parallelized checks across all presets, and verifies key flags and behaviors.

## What’s covered

- Presets: `light`, `standard`, `extreme`, `lossless`, `archive`
- Output handling: `-o` (explicit output), default naming (`_squeezed`), paths with spaces
- Estimation: `--dry-run` line appears with size + savings
- In-place mode: `--inplace` preserves original mtime (within a small tolerance)
- Filtering: `--include` / `--exclude` (both normal and recursive cases)
- Guard rails: `--skip-if-smaller`, `--min-gain`
- Parallelism: `--jobs` processes multiple files concurrently
- Quiet mode: `--quiet` suppresses the summary line
- Non-PDF inputs: are skipped without crashing
- Strength ordering: file sizes follow `extreme ≤ standard ≤ light` (with tolerance)

## Requirements

Install via Homebrew (same as the main tool):

```bash
brew install ghostscript pdfcpu
# Optional (nicer/faster fixtures & parallel runner):
brew install imagemagick gnu-parallel
```

> The suite will fall back to macOS `sips` if ImageMagick isn’t present.  
> GNU parallel is optional; the runner has a built-in fallback.

## Running

From the repo root:

```bash
# Quick health check (no heavy work):
make smoke

# Full suite (rebuilds fixtures, then runs everything):
make test
```

You can also run the scripts directly:

```bash
# Smoke test only
tests/smoke.sh

# Full suite (cleans/builds fixtures automatically)
tests/run.sh
```

Artifacts live under:

- `tests/assets/` – generated fixture images & PDFs
- `tests/build/` – logs, temp scripts, and test outputs
- `tests/assets-smoke/` – tiny fixture used only by `smoke.sh`

## Make targets

```bash
# Lint shell scripts (bash/zsh aware). Set FIX=1 to auto-format.
make lint            # env: FIX=0|1 (default 0), VERBOSE=0|1

# Smoke & full suite
make smoke
make test

# Clean generated assets & build artifacts (keeps compiled DT scripts)
make test-clean
```

Examples:

```bash
make lint VERBOSE=1        # show what would change
make lint FIX=1            # apply formatting fixes (default)
make test                  # run everything
make test-clean            # wipe tests/assets*, tests/build
```

## Environment variables

- `PDF_SQUEEZE_TEST_JOBS=<N>` – concurrency for the built-in runner (default: 4 if GNU parallel isn’t available).
- `VERBOSE=1` – more output from `lint`.
- `FIX=1` – auto-apply formatting in `lint`.

## Notes on determinism

- Fixtures are built from programmatic images and single-page PDFs to keep outputs stable across runs.
- When ImageMagick is unavailable, the suite falls back to `sips` and `ghostscript`, which may produce slightly different byte sizes, but tests account for small tolerances.
- Strength comparisons allow a 5% margin (to avoid false negatives due to encoder drift).

## Troubleshooting

- **“Missing: ghostscript” / “Missing: pdfcpu”**  
  Install the dependencies: `brew install ghostscript pdfcpu`.

- **Parallel test says “expected N outputs, got 0”**  
  Verify `pdf-squeeze` is executable at the repo root (`./pdf-squeeze`) or run `make install-bin` if you use that workflow.

- **Filters test fails**  
  The suite exercises both default output (`_squeezed.pdf`) and `--inplace` modes; ensure `--include`/`--exclude` patterns are POSIX ERE (like `grep -E`), and that your build hasn’t overridden those flags.

## CI (optional)

A sample GitHub Actions workflow is in `.github/workflows/test.yml`.  
If you don’t want CI, simply leave that directory out of your repo or disable the workflow.

---

Happy squeezing! If a case fails, see `tests/build/logs/*.log`—each test writes an executable “case script” plus stdout/stderr for quick repro.
