#!/bin/bash
# Run script for Ubuntu - handles line endings and execution
# This is the main script to run on Ubuntu

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    echo "WARNING: This script is designed for Ubuntu"
fi

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root"
    echo "Usage: sudo $0"
    exit 1
fi

echo "=== RG35HAXX Builder - Ubuntu Runner ==="
echo "Working directory: $SCRIPT_DIR"
echo

# CRITICAL: Fix line endings for ALL files first
echo "Fixing line endings for all files..."
find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "build*" -o -name "*config*" \) -exec dos2unix {} \; 2>/dev/null || {
    echo "dos2unix not found, using sed fallback..."
    find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "build*" -o -name "*config*" \) -exec sed -i 's/\r$//' {} \;
}

# Make ALL scripts executable
echo "Setting executable permissions..."
find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "build*" \) -exec chmod +x {} \;

echo "Starting RG35HAXX modular build process..."
echo

# Execute modular build script
exec "$SCRIPT_DIR/build.sh" "$@"
