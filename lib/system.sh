#!/bin/bash
# System utilities for RG35XX_H Custom Linux Builder


# Guard against multiple sourcing
[[ -n "${RG35HAXX_SYSTEM_LOADED:-}" ]] && return 0
export RG35HAXX_SYSTEM_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

check_root() {
    [[ $EUID -eq 0 ]] || error "Must run as root: sudo $0"
}

check_dependencies() {
    log_step "Checking dependencies"
    
    log_info "Updating package list..."
    apt update -qq
    
    local missing_packages=()
    
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            missing_packages+=("$pkg")
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${missing_packages[*]}"
        apt install -y "${missing_packages[@]}" || {
            log_warn "Some packages failed to install from repository"
            
            # Try manual installation for critical boot image tools
            if [[ " ${missing_packages[*]} " =~ " abootimg " ]]; then
                log_info "Attempting manual abootimg installation..."
                if ! command -v abootimg >/dev/null 2>&1; then
                    cd /tmp
                    git clone https://github.com/ggrandou/abootimg.git
                    cd abootimg
                    make && cp abootimg /usr/local/bin/
                    cd / && rm -rf /tmp/abootimg
                fi
            fi
            
            if [[ " ${missing_packages[*]} " =~ " android-tools-mkbootimg " ]]; then
                log_info "Attempting mkbootimg installation via pip..."
                command -v pip3 >/dev/null 2>&1 && pip3 install mkbootimg
            fi
        }
    fi

    # Verify critical commands
    local missing_commands=()
    for cmd in "${CRITICAL_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    # Check for boot image tools (at least one must be available, prefer abootimg)
    local boot_tools=("abootimg" "mkbootimg")
    local boot_tool_available=false
    local working_tool=""
    
    # Check abootimg first (preferred)
    if command -v abootimg >/dev/null 2>&1; then
        boot_tool_available=true
        working_tool="abootimg"
        log_success "Boot image tool available: abootimg (preferred)"
    elif command -v mkbootimg >/dev/null 2>&1; then
        # Test if mkbootimg actually works
        if mkbootimg --help >/dev/null 2>&1; then
            boot_tool_available=true
            working_tool="mkbootimg"
            log_success "Boot image tool available: mkbootimg"
        else
            log_warn "mkbootimg found but not working (gki dependency issues)"
        fi
    fi
    
    if [[ "$boot_tool_available" == "false" ]]; then
        log_error "No working boot image tools available! Need abootimg or working mkbootimg for RG35XX_H"
        log_info "Try installing abootimg: apt install abootimg"
        log_info "Or run: sudo ./install_dependencies.sh install"
        return 1
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Critical commands missing after installation: ${missing_commands[*]}"
        return 1
    fi

    log_success "All dependencies installed and verified"
}

check_build_environment() {
    log_step "Checking build environment"
    
    # Display CPU information
    local cpu_cores=$(nproc)
    local cpu_threads=$(nproc --all)
    log_info "CPU cores: $cpu_cores (threads: $cpu_threads)"
    log_info "Build jobs: $BUILD_JOBS (cores + 2 for I/O parallelism)"
    
    # Check available disk space (need at least 10GB)
    local available_space=$(df . | awk 'NR==2 {print $4}')
    local required_space=$((10 * 1024 * 1024)) # 10GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        log_error "Insufficient disk space. Need at least 10GB free."
        return 1
    fi
    log_info "Available disk space: $((available_space / 1024 / 1024))GB"
    
    # Check available memory
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_memory" -lt 2048 ]; then
        log_warn "Low available memory ($available_memory MB). Build may be slow."
    fi
    log_info "Available memory: ${available_memory}MB"
    
    log_success "Build environment optimized for maximum performance"
}

setup_build_environment() {
    log_step "Setting up build environment"
    
    # Create subdirectories if they don't exist
    mkdir -p "$BUILD_DIR"/{busybox,rootfs}
    mkdir -p "$OUTPUT_DIR"  # Persistent output directory
    if [[ ! -w "$OUTPUT_DIR" ]]; then
        log_error "Cannot write to output directory: $OUTPUT_DIR"
        exit 1
    fi
    mkdir -p "$TEMP_BUILD_DIR"  # Temporary work directory
    
    # Setup ccache for faster rebuilds
    setup_ccache
    
    log_info "Build directory: $BUILD_DIR (using existing)"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Temp directory: $TEMP_BUILD_DIR"
    
    # Check if linux directory exists
    if [[ -d "$BUILD_DIR/linux" ]]; then
        log_info "Found existing linux source directory"
    fi
}

setup_ccache() {
    if command -v ccache >/dev/null 2>&1; then
        export CCACHE_DIR="/tmp/ccache"
        export CCACHE_MAXSIZE="4G"
        export CCACHE_COMPRESS="true"
        mkdir -p "$CCACHE_DIR"
        
        # Setup ccache for cross compiler
        export CROSS_COMPILE="ccache aarch64-linux-gnu-"
        log_info "ccache enabled with 4GB cache"
    else
        log_warn "ccache not available, builds will be slower"
    fi
}

cleanup_build() {
    rm -rf "$BUILD_DIR" 2>/dev/null || true
}
