# Compiler and flags
CC = clang
CFLAGS = -O2 -Wall -Wextra
DEBUG_CFLAGS = -g -DDEBUG -O0
RELEASE_CFLAGS = -O2 -DNDEBUG
MACOS_CFLAGS = -mmacosx-version-min=10.14
FRAMEWORKS = -framework AppKit -framework Foundation

# Build output directory
TARGET_DIR = target

# Installation paths (customizable)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

# Default target
all: $(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-server

# Convenience targets
interface-mode: $(TARGET_DIR)/interface-mode
interface-mode-server: $(TARGET_DIR)/interface-mode-server
debug: $(TARGET_DIR)/interface-mode-debug $(TARGET_DIR)/interface-mode-server-debug

# Create target directory
$(TARGET_DIR):
	mkdir -p $(TARGET_DIR)

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

# Clean
clean:
	rm -rf $(TARGET_DIR)

# Test
test: $(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-server
	@echo "Testing interface-mode..."
	@$(TARGET_DIR)/interface-mode -h
	@echo "Testing interface-mode-server..."
	@$(TARGET_DIR)/interface-mode-server --help || true

# Quick check
check: clean all test

# Development
dev: $(TARGET_DIR)/interface-mode-server-debug
	@echo "Built debug version of server"

run-server: $(TARGET_DIR)/interface-mode-server
	@echo "Starting interface-mode-server..."
	@$(TARGET_DIR)/interface-mode-server

# Installation with customizable PREFIX
install: $(TARGET_DIR)/interface-mode $(TARGET_DIR)/interface-mode-server
	@echo "Installing to $(PREFIX)..."
	mkdir -p $(BINDIR)
	cp $(TARGET_DIR)/interface-mode $(BINDIR)/
	cp $(TARGET_DIR)/interface-mode-server $(BINDIR)/
	chmod +x $(BINDIR)/interface-mode
	chmod +x $(BINDIR)/interface-mode-server
	@echo "Installed interface-mode and interface-mode-server to $(BINDIR)"

# Uninstall from the same PREFIX
uninstall:
	@echo "Uninstalling from $(PREFIX)..."
	rm -f $(BINDIR)/interface-mode
	rm -f $(BINDIR)/interface-mode-server
	@echo "Removed interface-mode and interface-mode-server from $(BINDIR)"

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
	@echo "  all              - Build both programs (default)"
	@echo "  interface-mode   - Build original program"
	@echo "  interface-mode-server - Build server program"
	@echo "  debug            - Build debug versions"
	@echo "  clean            - Remove built executables"
	@echo "  test             - Run basic tests"
	@echo "  install          - Install to \$$PREFIX/bin (default: /usr/local/bin)"
	@echo "  uninstall        - Remove from \$$PREFIX/bin"
	@echo "  install-info     - Show installation configuration"
	@echo "  run-server       - Build and run server"
	@echo "  help             - Show this help"
	@echo ""
	@echo "Build output directory: $(TARGET_DIR)/"
	@echo ""
	@echo "Installation examples:"
	@echo "  make install                    # Install to /usr/local"
	@echo "  make install PREFIX=/opt/local  # Install to /opt/local"
	@echo "  make install PREFIX=\$$HOME/.local # Install to user directory"
	@echo "  sudo make install PREFIX=/usr   # Install system-wide"

.PHONY: all clean test check dev run-server install uninstall install-info help
