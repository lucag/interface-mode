# Compiler and flags
CC = clang
CFLAGS = -O2 -Wall -Wextra
DEBUG_CFLAGS = -g -DDEBUG -O0
RELEASE_CFLAGS = -O2 -DNDEBUG
MACOS_CFLAGS = -mmacosx-version-min=10.14
FRAMEWORKS = -framework AppKit -framework Foundation

# Build output directory
TARGET_DIR = target

UNAME := $(shell uname -s)

# Installation paths (customizable)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

ifeq ($(UNAME),Darwin)

PROGRAMS = interface-mode interface-mode-server

# Default target
all: $(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-server

# Convenience targets
interface-mode: $(TARGET_DIR)/interface-mode
interface-mode-server: $(TARGET_DIR)/interface-mode-server
debug: $(TARGET_DIR)/interface-mode-debug $(TARGET_DIR)/interface-mode-server-debug

# Original program (enhanced)
$(TARGET_DIR)/interface-mode: interface-mode.m makefile | $(TARGET_DIR)
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(RELEASE_CFLAGS) $< -o $@

# New server program
$(TARGET_DIR)/interface-mode-server: interface-mode-server.m makefile | $(TARGET_DIR)
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(RELEASE_CFLAGS) $< -o $@

# Debug versions
$(TARGET_DIR)/interface-mode-debug: interface-mode.m makefile | $(TARGET_DIR)
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(DEBUG_CFLAGS) $< -o $@

$(TARGET_DIR)/interface-mode-server-debug: interface-mode-server.m makefile | $(TARGET_DIR)
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(DEBUG_CFLAGS) $< -o $@

# Test
test: $(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-server
	@echo "Testing interface-mode..."
	@$(TARGET_DIR)/interface-mode -h
	@$(TARGET_DIR)/interface-mode --help
	@$(TARGET_DIR)/interface-mode --verbose
	@! $(TARGET_DIR)/interface-mode --invalid-option 2>/dev/null
	@echo "Testing interface-mode-server..."
	@$(TARGET_DIR)/interface-mode-server --help || true

# Development
dev: $(TARGET_DIR)/interface-mode-server-debug
	@echo "Built debug version of server"

run-server: $(TARGET_DIR)/interface-mode-server
	@echo "Starting interface-mode-server..."
	@$(TARGET_DIR)/interface-mode-server

define PLATFORM_HELP
	@echo "  all              - Build both programs (default)"
	@echo "  interface-mode   - Build original program"
	@echo "  interface-mode-server - Build server program"
	@echo "  debug            - Build debug versions"
	@echo "  test             - Run basic tests"
	@echo "  run-server       - Build and run server"
endef

else

PROGRAMS = interface-mode

# Default target
all: $(TARGET_DIR)/interface-mode

# Convenience targets
interface-mode: $(TARGET_DIR)/interface-mode
debug: $(TARGET_DIR)/interface-mode-debug

# Linux reads the desktop portal through GIO (docs/adr/0002). Ask the system
# pkg-config for it with its search path pinned, so a GLib from Linuxbrew or
# elsewhere on PATH can't leak into the build.
SYSTEM_PKG_CONFIG = /usr/bin/pkg-config
SYSTEM_PC_PATH := $(shell $(SYSTEM_PKG_CONFIG) --variable pc_path pkg-config)
GIO_CFLAGS := $(shell PKG_CONFIG_LIBDIR=$(SYSTEM_PC_PATH) $(SYSTEM_PKG_CONFIG) --cflags gio-2.0)
GIO_LIBS := $(shell PKG_CONFIG_LIBDIR=$(SYSTEM_PC_PATH) $(SYSTEM_PKG_CONFIG) --libs gio-2.0)
LINUX_SOURCES = cli.c portal.c
LINUX_HEADERS = interface-mode.h

# Release and debug builds differ only in their flags
$(TARGET_DIR)/interface-mode: BUILD_CFLAGS = $(RELEASE_CFLAGS)
$(TARGET_DIR)/interface-mode-debug: BUILD_CFLAGS = $(DEBUG_CFLAGS)
$(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-debug: $(LINUX_SOURCES) $(LINUX_HEADERS) makefile | $(TARGET_DIR)
	$(CC) $(CFLAGS) $(BUILD_CFLAGS) $(GIO_CFLAGS) $(LINUX_SOURCES) $(GIO_LIBS) -o $@

# Runs the binary against a fake desktop portal on a private session bus.
# Needs python3-dbusmock; the system python is used so the one it is
# installed for is the one that runs.
test: $(TARGET_DIR)/interface-mode
	INTERFACE_MODE=$(CURDIR)/$(TARGET_DIR)/interface-mode /usr/bin/python3 -m unittest discover -s tests -v

# Development
dev: $(TARGET_DIR)/interface-mode-debug
	@echo "Built debug version"

run-watch: $(TARGET_DIR)/interface-mode
	@echo "Starting interface-mode --watch..."
	@$(TARGET_DIR)/interface-mode --watch

define PLATFORM_HELP
	@echo "  all              - Build interface-mode (default)"
	@echo "  interface-mode   - Build interface-mode"
	@echo "  debug            - Build a debug version"
	@echo "  test             - Run the tests against a fake desktop portal"
	@echo "  run-watch        - Build and run interface-mode --watch"
endef

endif

# Create target directory
$(TARGET_DIR):
	mkdir -p $(TARGET_DIR)

# Clean
clean:
	rm -rf $(TARGET_DIR)

# Quick check
check: clean all test

# Build and run the Linux tests in Docker (tests/Dockerfile), from any host.
# The container works on a copy, so the host's target/ is left alone.
test-linux:
	docker build -q -t interface-mode-test tests
	docker run --rm -v "$(CURDIR)":/src:ro interface-mode-test \
		sh -c 'cp -r /src /w && cd /w && rm -rf $(TARGET_DIR) && make test'

# Installation with customizable PREFIX
install: $(addprefix $(TARGET_DIR)/,$(PROGRAMS))
	@echo "Installing to $(PREFIX)..."
	mkdir -p $(BINDIR)
	cp $^ $(BINDIR)/
	chmod +x $(addprefix $(BINDIR)/,$(PROGRAMS))
	@echo "Installed $(PROGRAMS) to $(BINDIR)"

# Uninstall from the same PREFIX
uninstall:
	@echo "Uninstalling from $(PREFIX)..."
	rm -f $(addprefix $(BINDIR)/,$(PROGRAMS))
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
	$(PLATFORM_HELP)
	@echo "  clean            - Remove built executables"
	@echo "  check            - Clean, build and test"
	@echo "  test-linux       - Run the Linux tests in Docker, from any host"
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

.PHONY: all clean test test-linux check dev run-server run-watch install uninstall install-info help
