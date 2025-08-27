# Makefile for pdf-squeeze project + DEVONthink scripts
# Typical use
# cd ~/Developer/pdf-squeeze
# make install-bin        # installs ./pdf-squeeze → ~/bin/pdf-squeeze (default)
# make compile            # compiles .applescript → .scpt into devonthink-scripts/compiled
# make install-dt         # copies compiled .scpt into DEVONthink’s App Scripts folder
# or do both:
# make install            # = install-bin + install-dt


SHELL := /bin/zsh
CUR := $(CURDIR)

# --- Layout inside your repo ---
DT_SRC_DIR := $(CUR)/devonthink-scripts/src
DT_OUT_DIR := $(CUR)/devonthink-scripts/compiled

# --- Where DEVONthink 4 loads .scpt from ---
DT_APP_SCRIPTS := $(HOME)/Library/Application Scripts/com.devon-technologies.think

# --- Where to install the pdf-squeeze CLI (no sudo) ---
# Prefer user bin; don’t use /usr/bin (system-protected). /usr/local/bin is also fine.
BIN_DIR ?= $(HOME)/bin

# --- Sources / Targets ---
SCRIPTS := $(wildcard $(DT_SRC_DIR)/*.applescript)
COMPILED := $(patsubst $(DT_SRC_DIR)/%.applescript,$(DT_OUT_DIR)/%.scpt,$(SCRIPTS))

# --- Default ---
.PHONY: all
all: compile

# --- Compile AppleScripts ---
.PHONY: compile
compile: $(COMPILED)

$(DT_OUT_DIR)/%.scpt: $(DT_SRC_DIR)/%.applescript
	@mkdir -p "$(DT_OUT_DIR)"
	@osacompile -o "$@" "$<"
	@echo "Compiled $< → $@"

# --- Install compiled .scpt into DEVONthink 4’s script folder ---
.PHONY: install-dt
install-dt: compile
	@mkdir -p "$(DT_APP_SCRIPTS)"
	@cp "$(DT_OUT_DIR)"/*.scpt "$(DT_APP_SCRIPTS)/"
	@echo "Installed DEVONthink scripts → $(DT_APP_SCRIPTS)"

# --- Install the pdf-squeeze CLI into BIN_DIR and make it executable ---
# If you prefer /usr/local/bin set BIN_DIR=/usr/local/bin when invoking make.
.PHONY: install-bin
install-bin:
	@mkdir -p "$(BIN_DIR)"
	@install -m 0755 pdf-squeeze "$(BIN_DIR)/pdf-squeeze"
	@echo "Installed pdf-squeeze → $(BIN_DIR)/pdf-squeeze"

# --- Convenience: everything ---
.PHONY: install
install: install-bin install-dt

# --- Clean compiled scripts (sources remain) ---
.PHONY: clean
clean:
	@rm -f "$(DT_OUT_DIR)"/*.scpt 2>/dev/null || true
	@echo "Cleaned compiled scripts in $(DT_OUT_DIR)"