
#!/bin/bash
# Configuration constants for RG35HAXX Custom Linux Builder

# Guard against multiple sourcing
[[ -n "${RG35HAXX_CONSTANTS_LOADED:-}" ]] && return 0
export RG35HAXX_CONSTANTS_LOADED=1

# Colors - export for use in all modules
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Build configuration
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUILD_DIR="$SCRIPT_DIR"  # Use the current script directory as build dir
export OUTPUT_DIR="$SCRIPT_DIR/build"  # Persistent output directory
export TEMP_BUILD_DIR="/tmp/rg35haxx_temp_$$"  # Temporary work directory
export LINUX_BRANCH="linux-6.10.y"
export BUSYBOX_VERSION="1.36.1"
export CROSS_COMPILE="aarch64-linux-gnu-"

# CPU optimization - use all available cores plus extra for I/O bound tasks
export MAX_CORES="$(nproc)"
export BUILD_JOBS="$((MAX_CORES + 4))"  # Even more aggressive for i5-12600K

# Speed optimization flags
export MAKEFLAGS="-j$BUILD_JOBS"
export CCACHE_DIR="/tmp/ccache"
export CCACHE_MAXSIZE="2G"

# Aggressive compiler optimizations for ARM64 cross-compilation
export EXTRA_CFLAGS="-O3 -march=armv8-a -mtune=cortex-a53 -flto -pipe -fno-plt"
export EXTRA_LDFLAGS="-flto -Wl,--as-needed"

# Device specific
export DEVICE_NAME="RG35HAXX"
export DEVICE_ARCH="ARM64"

# DTB variants for RG35XX H
export DTB_VARIANTS=(
  "sun50i-h700-anbernic-rg35xx-h.dtb"
  "sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb"
  "sun50i-h700-rg40xx-h.dtb"
)
export ACTIVE_DTB="${DTB_VARIANTS[0]}"  # Default

# Boot packaging modes
export PACKAGE_MODE="catdt"  # Options: "catdt" or "with-dt"

# Output file paths
export KERNEL_IMAGE="$OUTPUT_DIR/zImage-dtb"
export ROOTFS_ARCHIVE="$OUTPUT_DIR/rootfs.tar.gz"
export DEVICE_SOC="Allwinner H700"
export DEVICE_DTB="sun50i-h700-anbernic-rg35xx-h.dtb"
export DEVICE_DTS="sun50i-h700-anbernic-rg35xx-h.dts"

# Boot image defaults
export PAGE_SIZE="${PAGE_SIZE:-2048}"
export DEFAULT_CMDLINE="console=tty0 loglevel=7 ignore_loglevel"
export FORCE_CMDLINE="${FORCE_CMDLINE:-true}"   # can be toggled by --no-force-cmdline
export CUSTOM_CMDLINE="${CUSTOM_CMDLINE:-$DEFAULT_CMDLINE}"  # override with --cmdline=

# Legacy variable names for compatibility
export RG35XX_DTS="$DEVICE_DTS"
export H616_DTSI="sun50i-h616.dtsi"

# URLs
export DEVICE_TREE_URL="https://raw.githubusercontent.com/torvalds/linux/master/arch/arm64/boot/dts/allwinner"
export LINUX_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
export BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

# Package lists
export REQUIRED_PACKAGES=(
    "git" "make" "gcc" "bc" "bison" "flex" "libssl-dev" "libelf-dev"
    "gcc-aarch64-linux-gnu" "wget" "curl" "tar" "rsync" "cpio" "util-linux"
    "e2fsprogs" "device-tree-compiler" "build-essential" "ca-certificates" "pv"
    "ccache" "ninja-build" "moreutils" "parallel"  # Speed optimization tools
    "abootimg" "android-tools-mkbootimg" "android-tools-fsutils"  # Boot image tools for RG35XX_H
)

export CRITICAL_COMMANDS=(
    "aarch64-linux-gnu-gcc" "make" "git" "dtc" "mkfs.ext4"
)
