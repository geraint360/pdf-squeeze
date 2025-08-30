# Makefile for pdf-squeeze project + DEVONthink scripts
# Typical use
# cd pdf-squeeze
# make install-bin        # installs ./pdf-squeeze → ~/bin/pdf-squeeze (default)
# make compile            # compiles .applescript → .scpt into devonthink-scripts/compiled
# make install-dt         # copies compiled .scpt into DEVONthink’s App Scripts folder
# or do both:
# make install            # = install-bin + install-dt
SHELL := /bin/bash

REPO_ROOT      := $(CURDIR)
SRC_DIR        := devonthink-scripts/src
COMPILED_DIR   := devonthink-scripts/compiled

# DEVONthink version: 4 (default) or 3
DT_VER ?= 4

# Destination for pdf-squeeze
BIN_DIR ?= $(HOME)/bin

ifeq ($(DT_VER),4)
DT_BUNDLE := com.devon-technologies.think
else ifeq ($(DT_VER),3)
DT_BUNDLE := com.devon-technologies.think3
else
$(error DT_VER must be 3 or 4)
endif

DT_SCRIPTS_DIR := $(HOME)/Library/Application Scripts/$(DT_BUNDLE)

.PHONY: compile clean show-paths test test-clean install-bin install-dt install lint smoke fmt

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Targets:"
	@echo "  install-bin   Install ./pdf-squeeze -> ~/bin/pdf-squeeze"
	@echo "  compile       Compile AppleScripts -> devonthink-scripts/compiled"
	@echo "  install-dt    Copy compiled .scpt into DEVONthink App Scripts"
	@echo "  install       install-bin + install-dt"
	@echo "  test          Run test suite"
	@echo "  test-clean    Clean test artifacts"
	@echo "  clean         Remove compiled scripts"
	@echo "  show-paths    Print important paths"


# Convenience: install both the CLI and DEVONthink scripts
install: install-bin install-dt

show-paths:
	@echo "SRC_DIR:        $(SRC_DIR)"
	@echo "COMPILED_DIR:   $(COMPILED_DIR)"
	@echo "DT_VER:         $(DT_VER)"
	@echo "DT_SCRIPTS_DIR: $(DT_SCRIPTS_DIR)"

compile:
	@set -euo pipefail; \
	mkdir -p "$(COMPILED_DIR)"; \
	found=0; \
	while IFS= read -r -d '' f; do \
	  found=1; \
	  base="$${f##*/}"; \
	  out="$(COMPILED_DIR)/$${base%.applescript}.scpt"; \
	  echo "Compiling: $$f -> $$out"; \
	  osacompile -l AppleScript -o "$$out" "$$f"; \
	done < <(find "$(SRC_DIR)" -type f -name '*.applescript' -print0); \
	if [[ $$found -eq 0 ]]; then \
	  echo "No .applescript files found in $(SRC_DIR)"; \
	fi

install-dt: compile
	@set -euo pipefail; \
	mkdir -p "$(DT_SCRIPTS_DIR)"; \
	while IFS= read -r -d '' f; do \
	  echo "Installing: $$f -> $(DT_SCRIPTS_DIR)/$${f##*/}"; \
	  cp -f "$$f" "$(DT_SCRIPTS_DIR)/"; \
	done < <(find "$(COMPILED_DIR)" -type f -name '*.scpt' -print0); \
	echo "Installed to: $(DT_SCRIPTS_DIR)"

clean:
	@rm -rf "$(COMPILED_DIR)"
	@echo "Removed $(COMPILED_DIR)"

test:
	@chmod +x tests/*.sh
	@tests/run.sh

test-clean:
	@rm -rf tests/build tests/assets

# Install pdf-squeeze into ~/bin (create if missing)
install-bin:
	@mkdir -p "$(BIN_DIR)"
	@install -m 0755 pdf-squeeze "$(BIN_DIR)/pdf-squeeze"
	@echo "Installed to $(BIN_DIR)/pdf-squeeze"
	@case ":$(PATH):" in *:"$(BIN_DIR)":*) ;; *) echo 'NOTE: add $(BIN_DIR) to your PATH';; esac

lint:
	@VERBOSE=$(VERBOSE) FIX=$(FIX) bash scripts/lint.sh

smoke:
	@tests/smoke.sh

fmt:
	@scripts/format.sh
	