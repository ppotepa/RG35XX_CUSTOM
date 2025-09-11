#!/bin/bash
# debug_build_issue.sh - Debug script to help identify build issues

echo "==============================================="
echo "RG35XX-H Build Debug Information"
echo "==============================================="

# Check environment
echo "Environment Information:"
echo "- Current directory: $(pwd)"
echo "- Script directory: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "- User: $(whoami)"
echo "- OS: $(uname -a)"
echo

# Check if device nodes exist
echo "Device Node Check:"
EMMC_DEV="${EMMC_DEV:-/dev/mmcblk0}"
BOOT_PART="${BOOT_PART:-${EMMC_DEV}p4}"
ROOT_PART="${ROOT_PART:-${EMMC_DEV}p5}"

echo "- EMMC_DEV: $EMMC_DEV"
if [[ -b "$EMMC_DEV" ]]; then
    echo "  ✓ Block device exists"
    echo "  Device info:"
    lsblk "$EMMC_DEV" 2>/dev/null || echo "  Warning: lsblk failed"
else
    echo "  - Not a block device (build environment)"
fi

echo "- BOOT_PART: $BOOT_PART"
if [[ -b "$BOOT_PART" ]]; then
    echo "  ✓ Boot partition exists"
else
    echo "  - Boot partition not found (build environment)"
fi

echo "- ROOT_PART: $ROOT_PART"
if [[ -b "$ROOT_PART" ]]; then
    echo "  ✓ Root partition exists"
else
    echo "  - Root partition not found (build environment)"
fi
echo

# Check required tools
echo "Tool Availability:"
tools=("git" "make" "gcc" "lsblk" "sgdisk" "parted" "dd" "mkbootimg" "abootimg" "unmkbootimg" "magiskboot")
for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✓ $tool: $(which "$tool")"
    else
        echo "  - $tool: not found"
    fi
done
echo

# Check directory structure
echo "Directory Structure:"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
required_dirs=("config" "core" "lib" "modules" "builders" "plugins" "tools" "flash")
for dir in "${required_dirs[@]}"; do
    if [[ -d "$SCRIPT_DIR/$dir" ]]; then
        file_count=$(find "$SCRIPT_DIR/$dir" -name "*.sh" | wc -l)
        echo "  ✓ $dir/ ($file_count shell scripts)"
    else
        echo "  - $dir/ missing"
    fi
done
echo

# Check key files
echo "Key Files:"
key_files=("main.sh" "config/constants.sh" "lib/logger.sh" "core/build_rg35xxh.sh")
for file in "${key_files[@]}"; do
    if [[ -f "$SCRIPT_DIR/$file" ]]; then
        echo "  ✓ $file"
        # Check if it's executable
        if [[ -x "$SCRIPT_DIR/$file" ]]; then
            echo "    (executable)"
        else
            echo "    (not executable - run chmod +x)"
        fi
    else
        echo "  - $file missing"
    fi
done
echo

# Check config files
echo "Configuration Files:"
if [[ -f "$SCRIPT_DIR/config/constants.sh" ]]; then
    echo "  ✓ constants.sh exists"
    # Check if it sources without errors
    if source "$SCRIPT_DIR/config/constants.sh" 2>/dev/null; then
        echo "    (sources successfully)"
    else
        echo "    (sourcing failed)"
    fi
fi

if [[ -f "$SCRIPT_DIR/config/config_patch" ]]; then
    echo "  ✓ config_patch exists"
elif [[ -d "$SCRIPT_DIR/config/config_patch" ]]; then
    echo "  ✓ config_patch directory exists"
    config_files=$(find "$SCRIPT_DIR/config/config_patch" -name "*.config" | wc -l)
    echo "    ($config_files config files)"
else
    echo "  - config_patch missing"
fi
echo

# Test build environment detection
echo "Build Environment Detection Test:"
if [[ -b "$EMMC_DEV" ]]; then
    echo "  Environment: TARGET DEVICE"
    echo "  - Will perform device operations"
    echo "  - Will backup partitions"
    echo "  - Will flash to device"
else
    echo "  Environment: BUILD SYSTEM (Ubuntu/development)"
    echo "  - Will skip device operations"
    echo "  - Will create build artifacts only"
    echo "  - Will not flash to device"
fi
echo

# Check if main.sh can be executed
echo "Main Script Test:"
if [[ -x "$SCRIPT_DIR/main.sh" ]]; then
    echo "  ✓ main.sh is executable"
    if "$SCRIPT_DIR/main.sh" --help >/dev/null 2>&1; then
        echo "  ✓ main.sh runs successfully"
    else
        echo "  - main.sh failed to run"
        echo "  Error output:"
        "$SCRIPT_DIR/main.sh" --help 2>&1 | head -5 | sed 's/^/    /'
    fi
else
    echo "  - main.sh is not executable"
    echo "  Run: chmod +x main.sh"
fi
echo

echo "==============================================="
echo "Debug Complete"
echo "==============================================="

# Recommendations
echo "Recommendations:"
if [[ ! -b "$EMMC_DEV" ]]; then
    echo "1. You're in a build environment - this is correct for Ubuntu"
    echo "2. The script should automatically detect this and skip device operations"
    echo "3. If you see device-related errors, the detection logic may need fixing"
fi

if [[ ! -x "$SCRIPT_DIR/main.sh" ]]; then
    echo "4. Make scripts executable: chmod +x *.sh"
fi

echo "5. To run build: ./main.sh --build-rg35xxh"
echo "6. To install deps: ./main.sh --install-deps"
