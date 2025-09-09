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

echo "=== RG35XX_H Builder - Ubuntu Runner ==="
echo "Working directory: $SCRIPT_DIR"
echo

# Fix line endings for all script files
echo "Fixing line endings..."
find "$SCRIPT_DIR" -name "*.sh" -exec sed -i 's/\r$//' {} \;
find "$SCRIPT_DIR" -name "*config*" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

# Make scripts executable
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

echo "Starting build process..."
echo

# Execute main build script
exec "$SCRIPT_DIR/build_rg35xx.sh" "$@"
