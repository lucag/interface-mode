# Interface Mode Tools

A couple of macOS utilities for detecting and monitoring the system's interface mode (light/dark).

## Programs

### `interface-mode`

A simple utility that checks the current macOS interface mode and exits with appropriate status codes.

**Usage:**

```bash
./interface-mode [ -v | -h ]
```

**Options:**

- `-v`: Verbose output - prints "Light" or "Dark"
- `-h`: Help - shows usage information

**Exit codes:**

- `0`: Light mode
- `-1`: Dark mode

**Example:**

```bash
./interface-mode -v
# Output: Light
```

### `interface-mode-server`

A server that continuously monitors macOS interface mode changes and outputs
messages when the state changes.

**Usage:**

```bash
./interface-mode-server [OPTIONS]
```

**Options:**

- `-j, --json`: Output in JSON format (default)
- `-s, --simple`: Output simple text format
- `-h, --help`: Show help message

**Output formats:**

JSON format (default):

```json
{"timestamp":"2024-01-15T14:30:25.123Z","mode":"dark","change":"light_to_dark"}
```

Simple format:

```
light
dark
```

**Example:**

```bash
# Start monitoring with JSON output
./interface-mode-server

# Start monitoring with simple output
./interface-mode-server --simple

# Stop the server with Ctrl+C
```

## Project Structure

```
interface-mode/
├── interface-mode.m          # Original interface mode checker
├── interface-mode-server.m   # Continuous monitoring server
├── makefile                  # Build system
├── README.md                 # This documentation
├── .gitignore               # Git ignore rules
└── target/                  # Build output directory (created by make)
    ├── interface-mode       # Compiled original program
    ├── interface-mode-server # Compiled server program
    └── *.dSYM/             # Debug symbols (if built with debug)
```

## Building

### Prerequisites
- macOS with Xcode Command Line Tools
- clang compiler

### Build Commands

```bash
# Build both programs
make all

# Build individual programs
make interface-mode
make interface-mode-server

# Build debug versions
make debug

# Clean build artifacts
make clean

# Run tests
make test
```

**Note**: All executables are built in the `target/` directory to keep the project root clean.

## Installation

### Default Installation

```bash
# Install to /usr/local/bin (requires sudo)
sudo make install

# Install to user directory
make install PREFIX=$HOME/.local
```

### Custom Installation Location

```bash
# Install to custom location
make install PREFIX=/opt/local

# Install system-wide
sudo make install PREFIX=/usr
```

### Uninstallation

```bash
# Uninstall from the same PREFIX used for installation
make uninstall PREFIX=/usr/local
```

### Installation Information

```bash
# Show current installation configuration
make install-info
```

## Development

### Available Make Targets

```bash
make help          # Show all available targets
make dev           # Build debug version of server
make run-server    # Build and run server
make check         # Clean, build, and test everything
```

### Signal Handling

The server responds to:

- `SIGINT` (Ctrl+C): Graceful shutdown
- `SIGTERM`: Graceful shutdown

## Technical Details

### How It Works

Both programs use the macOS AppKit framework to detect the current interface mode:

1. **Current Mode Detection**: Uses `NSApplication.sharedApplication.effectiveAppearance`
2. **Change Monitoring**: Uses Key-Value Observing (KVO) on the `effectiveAppearance` property
3. **Event Handling**: Listens for `NSApplicationDidChangeScreenParametersNotification`

### Dependencies

- **AppKit**: For appearance detection and monitoring
- **Foundation**: For basic Objective-C functionality

### Compilation

```bash
clang -framework AppKit -framework Foundation -O2 source.m -o target/executable
```

## Use Cases

### `interface-mode`

- Shell scripts that need to adapt to system appearance
- CI/CD pipelines that test appearance-dependent features
- Automation scripts that change behavior based on mode

### `interface-mode-server`

- Real-time monitoring of appearance changes
- Integration with other applications that need appearance events
- Web applications that sync with system appearance
- Home automation triggers based on appearance changes

## Examples

### Shell Script Integration

```bash
#!/bin/bash
if ./interface-mode; then
    echo "System is in light mode"
else
    echo "System is in dark mode"
fi
```

### JSON Processing

```bash
# Monitor changes and process with jq
./interface-mode-server | while read line; do
    mode=$(echo "$line" | jq -r '.mode')
    echo "Switched to $mode mode"
done
```

### Simple Monitoring

```bash
# Just get mode changes as simple text
./interface-mode-server --simple | while read mode; do
    echo "Mode changed to: $mode"
done
```

## License

This project is open source. Feel free to use and modify as needed.

