#!/bin/bash
# Configuration constants for RG35XX_H Custom Linux Builder
# Contains all shared variables and constants used across the build system
# This file must be sourced by all scripts that need access to these values

# Guard against multiple sourcing (do not export the guard; keep it shell-local)
[[ -n "${RG35HAXX_CONSTANTS_LOADED:-}" ]] && return 0
RG35HAXX_CONSTANTS_LOADED=1

# Set strict mode for better error handling
set -o pipefail

# ANSI colors for consistent UI - export for use in all modules
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# ===================================
# PATH AND DIRECTORY CONFIGURATION
# ===================================
# Base paths - all other paths are derived from these
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/build}"  # Allow override from environment
export OUTPUT_DIR="${OUTPUT_DIR:-$BUILD_DIR/output}"  # Persistent output directory
export TEMP_BUILD_DIR="${TEMP_BUILD_DIR:-/tmp/rg35xx_build_$$}"  # Temporary work directory
export LOG_DIR="${LOG_DIR:-$BUILD_DIR/logs}"  # Directory for build logs

# ===================================
# BUILD CONFIGURATION
# ===================================
# Version control
export LINUX_BRANCH="${LINUX_BRANCH:-linux-6.10.y}"  # Linux kernel branch
export BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"  # BusyBox version

# Compiler configuration
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"  # Cross compiler prefix
export ARCH="arm64"  # Architecture 
export SUBARCH="arm64"

# Optimization flags
export MAX_CORES="$(nproc 2>/dev/null || echo 2)"  # Get number of CPU cores, fallback to 2
export BUILD_JOBS="${BUILD_JOBS:-$((MAX_CORES + 2))}"  # Balance between performance and stability
export MAKEFLAGS="-j$BUILD_JOBS"
export FORCE_REBUILD="${FORCE_REBUILD:-false}"  # Force clean rebuild of everything

# Compiler optimizations for ARM64 cross-compilation
export EXTRA_CFLAGS="-O2 -march=armv8-a -mtune=cortex-a53 -pipe"  # More stable than -O3
export EXTRA_LDFLAGS="-Wl,--as-needed"  # Reduce binary size

# CCache configuration for faster rebuilds
export CCACHE_DIR="${CCACHE_DIR:-/tmp/ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"

# ===================================
# DEVICE CONFIGURATION
# ===================================
export DEVICE_NAME="RG35XX-H"  # User-friendly device name
export DEVICE_SOC="Allwinner H700"  # SoC information
export DEVICE_ARCH="arm64"  # Architecture

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

# ===================================
# BOOT IMAGE CONFIGURATION
# ===================================
# Boot image parameters
export PAGE_SIZE="${PAGE_SIZE:-2048}"  # Default page size for boot image

# Research-backed cmdline template for RG35XX-H LCD console visibility
# Based on Knulli project and Allwinner H700 community documentation
# ROOT_PARTITION will be dynamically replaced by build script with detected partition
export KCMD_TEMPLATE="root=ROOT_PARTITION rw rootwait console=tty0 loglevel=7 ignore_loglevel fbcon=map:1 fbcon=nodefer video=640x480-32 vt.global_cursor_default=0"

# Default cmdline with fallback root partition
export DEFAULT_CMDLINE="root=/dev/sdc5 rw rootwait console=tty0 loglevel=7 ignore_loglevel fbcon=map:1 fbcon=nodefer video=640x480-32 vt.global_cursor_default=0"

# Command line configuration
export FORCE_CMDLINE="${FORCE_CMDLINE:-true}"   # Force kernel command line in build
export CUSTOM_CMDLINE="${CUSTOM_CMDLINE:-$DEFAULT_CMDLINE}"  # Allow override via CLI with --cmdline=

# A breakdown of the LCD console visibility parameters:
# - console=tty0: Direct console output to LCD display
# - fbcon=nodefer: Force immediate framebuffer console takeover
# - fbcon=map:1: Map console to primary framebuffer device
# - video=640x480-32: Set correct mode for RG35XX-H display
# - vt.global_cursor_default=0: Disable blinking cursor

# Dynamic device detection for RG35XX-H
# These will be set by auto-detection or fallback to /dev/sdc based on verified lsblk
export RG35XX_DEVICE="${RG35XX_DEVICE:-}"  # Will be auto-detected
export RG35XX_BOOT_PART="${RG35XX_BOOT_PART:-}"  # Will be auto-detected  
export RG35XX_ROOT_PART="${RG35XX_ROOT_PART:-}"  # Will be auto-detected

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
    "mkbootimg" "android-sdk-libsparse-utils"  # Updated package names for boot image tools
)

export CRITICAL_COMMANDS=(
    "aarch64-linux-gnu-gcc" "make" "git" "dtc" "mkfs.ext4"
)
