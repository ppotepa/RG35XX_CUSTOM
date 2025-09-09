#!/bin/bash
# Configuration constants for RG35XX_H Custom Linux Builder

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Build configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="/tmp/rg35xx_build_$$"
readonly LINUX_BRANCH="linux-6.10.y"
readonly BUSYBOX_VERSION="1.36.1"
readonly CROSS_COMPILE="aarch64-linux-gnu-"

# Hardware specific
readonly DEVICE_TREE_URL="https://raw.githubusercontent.com/torvalds/linux/master/arch/arm64/boot/dts/allwinner"
readonly RG35XX_DTS="sun50i-h700-anbernic-rg35xx-h.dts"
readonly H616_DTSI="sun50i-h616.dtsi"

# Package lists
readonly REQUIRED_PACKAGES=(
    "git" "make" "gcc" "bc" "bison" "flex" "libssl-dev" "libelf-dev"
    "gcc-aarch64-linux-gnu" "wget" "curl" "tar" "rsync" "cpio" "util-linux"
    "e2fsprogs" "device-tree-compiler" "build-essential" "ca-certificates" "pv"
)

readonly CRITICAL_COMMANDS=(
    "aarch64-linux-gnu-gcc" "make" "git" "dtc" "mkfs.ext4"
)
