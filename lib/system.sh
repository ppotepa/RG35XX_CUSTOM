#!/bin/bash
# System utilities for RG35XX_H Custom Linux Builder

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

check_root() {
    [[ $EUID -eq 0 ]] || error "Must run as root: sudo $0"
}

check_dependencies() {
    step "Checking dependencies"
    
    log "Updating package list..."
    apt update -qq
    
    local missing_packages=()
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log "Installing missing packages: ${missing_packages[*]}"
        apt install -y "${missing_packages[@]}" || error "Failed to install packages"
    fi
    
    for cmd in "${CRITICAL_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Critical command missing after installation: $cmd"
        fi
    done
    
    log "All dependencies installed and verified"
}

setup_build_environment() {
    step "Setting up build environment"
    mkdir -p "$BUILD_DIR"/{linux,busybox,rootfs,out}
    log "Build directory: $BUILD_DIR"
}

cleanup_build() {
    rm -rf "$BUILD_DIR" 2>/dev/null || true
}
