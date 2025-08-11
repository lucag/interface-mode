# Compiler and flags
CC = clang
CFLAGS = -O2 -Wall -Wextra
DEBUG_CFLAGS = -g -DDEBUG -O0
RELEASE_CFLAGS = -O2 -DNDEBUG
MACOS_CFLAGS = -mmacosx-version-min=10.14
FRAMEWORKS = -framework AppKit -framework Foundation

# Installation paths (customizable)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

# Default target
all: interface-mode interface-mode-server

# Original program (enhanced)
interface-mode: interface-mode.m makefile
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(RELEASE_CFLAGS) $< -o $@

# New server program
interface-mode-server: interface-mode-server.m makefile
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(RELEASE_CFLAGS) $< -o $@

# Debug versions
interface-mode-debug: interface-mode.m makefile
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(DEBUG_CFLAGS) $< -o $@

interface-mode-server-debug: interface-mode-server.m makefile
	$(CC) $(MACOS_CFLAGS) $(FRAMEWORKS) $(DEBUG_CFLAGS) $< -o $@

# Clean
clean:
	rm -f interface-mode interface-mode-server
	rm -f interface-mode-debug interface-mode-server-debug

# Test
test: interface-mode interface-mode-server
	@echo "Testing interface-mode..."
	@./interface-mode -h
	@echo "Testing interface-mode-server..."
	@./interface-mode-server --help || true

# Quick check
check: clean all test

# Development
dev: interface-mode-server-debug
	@echo "Built debug version of server"

run-server: interface-mode-server
	@echo "Starting interface-mode-server..."
	@./interface-mode-server

# Installation with customizable PREFIX
install: interface-mode interface-mode-server
	@echo "Installing to $(PREFIX)..."
	mkdir -p $(BINDIR)
	cp interface-mode $(BINDIR)/
	cp interface-mode-server $(BINDIR)/
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
	@echo "Installation examples:"
	@echo "  make install                    # Install to /usr/local"
	@echo "  make install PREFIX=/opt/local  # Install to /opt/local"
	@echo "  make install PREFIX=\$$HOME/.local # Install to user directory"
	@echo "  sudo make install PREFIX=/usr   # Install system-wide"

.PHONY: all clean test check dev run-server install uninstall install-info help
