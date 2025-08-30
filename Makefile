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

ifeq ($(DT_VER),4)
DT_BUNDLE := com.devon-technologies.think
else ifeq ($(DT_VER),3)
DT_BUNDLE := com.devon-technologies.think3
else
$(error DT_VER must be 3 or 4)
endif

DT_SCRIPTS_DIR := $(HOME)/Library/Application Scripts/$(DT_BUNDLE)

.PHONY: compile install-scripts clean show-paths test test-clean

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

install-scripts: compile
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
