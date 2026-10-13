# Compiler and flags
CC = clang
CFLAGS = -Wall -Wextra
DEBUG_CFLAGS = -g -DDEBUG -O0
RELEASE_CFLAGS = -O2 -DNDEBUG

# Build output directory
TARGET_DIR = target

UNAME := $(shell uname -s)

# Installation paths (customizable)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

PROGRAMS = interface-mode
# Programs earlier versions installed: install and uninstall remove them.
OBSOLETE_PROGRAMS = interface-mode-server

# The command-line contract is shared; each platform adds a backend behind
# interface-mode.h (docs/adr/0002) and its own test suite.
SOURCES = cli.c stop.c
HEADERS = interface-mode.h stop.h

ifeq ($(UNAME),Darwin)

# macOS reads the Interface Mode through AppKit, so it builds with Apple's
# compiler, whatever clang comes first on PATH.
CC = xcrun clang
COMPILER = $(shell xcrun --find clang) -isysroot $(shell xcrun --show-sdk-path)
SOURCES += macos.m
PLATFORM_CFLAGS = -mmacosx-version-min=10.14 -fobjc-arc
PLATFORM_LIBS = -framework AppKit -framework Foundation
# The Interface Mode can't be set without changing it for the user, so this
# tests only the contract around it.
TEST_SUITE = test_macos.py
TEST_HELP = Run the contract tests

else

# Linux reads the desktop portal through GIO. Ask the system pkg-config for
# it with its search path pinned, so a GLib from Linuxbrew or elsewhere on
# PATH can't leak into the build.
SOURCES += portal.c
COMPILER = $(shell command -v $(CC))
SYSTEM_PKG_CONFIG = /usr/bin/pkg-config
SYSTEM_PC_PATH := $(shell $(SYSTEM_PKG_CONFIG) --variable pc_path pkg-config)
PLATFORM_CFLAGS := $(shell PKG_CONFIG_LIBDIR=$(SYSTEM_PC_PATH) $(SYSTEM_PKG_CONFIG) --cflags gio-2.0)
PLATFORM_LIBS := $(shell PKG_CONFIG_LIBDIR=$(SYSTEM_PC_PATH) $(SYSTEM_PKG_CONFIG) --libs gio-2.0)
# Runs the binary against a fake desktop portal on a private session bus.
# Needs python3-dbusmock.
TEST_SUITE = test_linux.py
TEST_HELP = Run the tests against a fake desktop portal

endif

# Default target
all: $(TARGET_DIR)/interface-mode

# Convenience targets
interface-mode: $(TARGET_DIR)/interface-mode
debug: $(TARGET_DIR)/interface-mode-debug

# Release and debug builds differ only in their flags
$(TARGET_DIR)/interface-mode: BUILD_CFLAGS = $(RELEASE_CFLAGS)
$(TARGET_DIR)/interface-mode-debug: BUILD_CFLAGS = $(DEBUG_CFLAGS)
$(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-debug: $(SOURCES) $(HEADERS) makefile | $(TARGET_DIR)
	$(CC) $(CFLAGS) $(BUILD_CFLAGS) $(PLATFORM_CFLAGS) $(SOURCES) $(PLATFORM_LIBS) -o $@

# The system python, so the one any test dependency is installed for is the
# one that runs.
test: $(TARGET_DIR)/interface-mode
	INTERFACE_MODE=$(CURDIR)/$(TARGET_DIR)/interface-mode /usr/bin/python3 -m unittest discover -s tests -p $(TEST_SUITE) -v

# Development
dev: $(TARGET_DIR)/interface-mode-debug
	@echo "Built debug version"

run-watch: $(TARGET_DIR)/interface-mode
	@echo "Starting interface-mode --watch..."
	@$(TARGET_DIR)/interface-mode --watch

# Create target directory
$(TARGET_DIR):
	mkdir -p $(TARGET_DIR)

# How each source is compiled on this platform, for clangd and other tools.
# Written from the build's own sources and flags, so it can't drift from them.
compile_commands.json:
	@{ echo '['; sep=; for f in $(SOURCES); do \
	  printf '%s  {"directory": "%s", "file": "%s", "command": "%s"}\n' "$$sep" \
	    "$(CURDIR)" "$$f" "$(COMPILER) $(CFLAGS) $(RELEASE_CFLAGS) $(PLATFORM_CFLAGS) -c $$f"; \
	  sep=,; done; echo ']'; } > $@
	@echo "Wrote $@"

# Use the tracked git hooks (.githooks): commit messages must name an issue.
hooks:
	git config core.hooksPath .githooks

# Clean
clean:
	rm -rf $(TARGET_DIR)

# Quick check
check: clean all test

# Build and run the Linux tests in Docker (tests/Dockerfile), from any host.
# The container works on a copy, so the host's target/ is left alone.
test-linux:
	@docker info >/dev/null 2>&1 || { echo "test-linux: Docker isn't running; start it (on macOS: open -a Docker)" >&2; exit 1; }
	docker build -q -t interface-mode-test tests
	docker run --rm -v "$(CURDIR)":/src:ro interface-mode-test \
		sh -c 'cp -r /src /w && cd /w && rm -rf $(TARGET_DIR) && make test'

# Installation with customizable PREFIX
install: $(addprefix $(TARGET_DIR)/,$(PROGRAMS))
	@echo "Installing to $(PREFIX)..."
	mkdir -p $(BINDIR)
	cp $^ $(BINDIR)/
	chmod +x $(addprefix $(BINDIR)/,$(PROGRAMS))
	rm -f $(addprefix $(BINDIR)/,$(OBSOLETE_PROGRAMS))
	@echo "Installed $(PROGRAMS) to $(BINDIR)"

# Uninstall from the same PREFIX
uninstall:
	@echo "Uninstalling from $(PREFIX)..."
	rm -f $(addprefix $(BINDIR)/,$(PROGRAMS) $(OBSOLETE_PROGRAMS))
	@echo "Removed $(PROGRAMS) from $(BINDIR)"

# Show installation info
install-info:
	@echo "Installation configuration:"
	@echo "  PREFIX: $(PREFIX)"
	@echo "  BINDIR: $(BINDIR)"
	@echo "  MANDIR: $(MANDIR)"
	@echo ""
	@echo "To install with custom prefix:"
	@echo "  make install PREFIX=/opt/local"
	@echo "  make install PREFIX=$$HOME/.local"
	@echo "  sudo make install PREFIX=/usr"

# Help
help:
	@echo "Available targets:"
	@echo "  all              - Build interface-mode (default)"
	@echo "  interface-mode   - Build interface-mode"
	@echo "  debug            - Build a debug version"
	@echo "  test             - $(TEST_HELP)"
	@echo "  run-watch        - Build and run interface-mode --watch"
	@echo "  clean            - Remove built executables"
	@echo "  check            - Clean, build and test"
	@echo "  test-linux       - Run the Linux tests in Docker, from any host"
	@echo "  compile_commands.json - Write the compilation database for clangd"
	@echo "  hooks            - Use the repo's git hooks (commit messages name an issue)"
	@echo "  install          - Install to \$$PREFIX/bin (default: /usr/local/bin)"
	@echo "  uninstall        - Remove from \$$PREFIX/bin"
	@echo "  install-info     - Show installation configuration"
	@echo "  help             - Show this help"
	@echo ""
	@echo "Build output directory: $(TARGET_DIR)/"
	@echo ""
	@echo "Installation examples:"
	@echo "  make install                    # Install to /usr/local"
	@echo "  make install PREFIX=/opt/local  # Install to /opt/local"
	@echo "  make install PREFIX=\$$HOME/.local # Install to user directory"
	@echo "  sudo make install PREFIX=/usr   # Install system-wide"

.PHONY: all clean test test-linux hooks compile_commands.json check dev run-watch install uninstall install-info help
