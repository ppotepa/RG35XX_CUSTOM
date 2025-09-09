#!/bin/bash
# Quick debug script to test logger functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

echo "=== Debug Test ==="
echo "Script dir: $SCRIPT_DIR"

echo "Testing constants source..."
source "$SCRIPT_DIR/config/constants.sh" && echo "✅ Constants loaded" || echo "❌ Constants failed"

echo "Testing logger source..."
source "$SCRIPT_DIR/lib/logger.sh" && echo "✅ Logger loaded" || echo "❌ Logger failed"

echo "Testing log functions..."
if command -v log_info >/dev/null 2>&1; then
    echo "✅ log_info function exists"
    log_info "Test info message"
else
    echo "❌ log_info function missing"
fi

if command -v log_error >/dev/null 2>&1; then
    echo "✅ log_error function exists"
    log_error "Test error message (non-fatal)"
else
    echo "❌ log_error function missing"
fi

echo "=== Debug Complete ==="
