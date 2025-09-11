#!/bin/bash
# System utilities for RG35XX_H Custom Linux Builder
# Handles environment setup, dependency checking, and common system operations
# Enhanced with better error handling, workspace validation, and performance optimization

# Guard against multiple sourcing (do not export the guard; keep it shell-local)
[[ -n "${RG35HAXX_SYSTEM_LOADED:-}" ]] && return 0
RG35HAXX_SYSTEM_LOADED=1

# Import logger
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Set up error handling
set -o pipefail
set -o errtrace # Make sure error traps are inherited by functions and subshells

# Trap errors for better reporting and debugging
trap 'handle_error "${BASH_SOURCE[0]}:${LINENO}:${FUNCNAME[0]:-main}" ${?} || exit 1' ERR
trap 'log_info "Script interrupted. Cleaning up..."; handle_cleanup; exit 130' INT

# Enhanced error handling with detailed debugging information
handle_error() {
    local location="$1"
    local exit_code="${2:-1}"
    
    log_error "Error in $location (exit code: $exit_code)"
    
    # Show stack trace for better debugging
    local frame=0
    while caller $frame; do
        ((frame++))
    done | awk '{print "  " NR ": " $3 ":" $1 " (" $2 ")"}' | while read -r line; do
        log_debug "$line"
    done
    
    # Return the original error code to allow for conditional handling
    return $exit_code
}

# Cleanup handler for interrupted scripts
handle_cleanup() {
    # Clean up any temporary files or processes
    if [[ -n "${TEMP_FILES[@]:-}" ]]; then
        log_debug "Cleaning up temporary files..."
        rm -f "${TEMP_FILES[@]}" 2>/dev/null || true
    fi
    
    # Kill any background processes started by this script
    if [[ -n "${BG_PIDS[@]:-}" ]]; then
        log_debug "Terminating background processes: ${BG_PIDS[*]}"
        kill "${BG_PIDS[@]}" 2>/dev/null || true
    fi
}

# Check if running as root and handle accordingly
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run with: sudo $(basename "$0") $*"
        return 1
    fi
    
    log_debug "Running with root privileges (UID: $EUID)"
    return 0
}

check_dependencies() {
    log_step "Checking dependencies"
    
    # Skip update if no package manager or not in interactive mode
    local skip_update="${SKIP_APT_UPDATE:-false}"
    local interactive="${INTERACTIVE:-true}"
    
    if [[ "$skip_update" == "false" ]]; then
        if command -v apt >/dev/null 2>&1; then
            log_info "Updating package list..."
            apt update -qq || {
                log_warn "Package list update failed, continuing with existing cache"
                # Create a timestamp file to avoid repeated update attempts
                touch "/tmp/rg35xx_apt_update_attempted"
            }
        else
            log_warn "APT package manager not found, package installation may be limited"
            skip_update="true"
        fi
    else
        log_debug "Skipping package list update as requested"
    fi
    
    # Check for minimal required utilities
    for util in "make" "gcc" "wget" "tar"; do
        if ! command -v "$util" >/dev/null 2>&1; then
            log_error "Essential utility '$util' not found. Cannot continue."
            log_info "Please install build-essential package manually"
            return 1
        fi
    done
    
    # Check and install packages
    local missing_packages=()
    local distro_id=""
    
    # Detect distribution if possible
    if command -v lsb_release >/dev/null 2>&1; then
        distro_id=$(lsb_release -si 2>/dev/null)
    elif [ -f /etc/os-release ]; then
        distro_id=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
    fi
    log_debug "Detected distribution: ${distro_id:-unknown}"
    
    # First pass: check which packages are missing
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if command -v apt >/dev/null 2>&1; then
            # Debian/Ubuntu style check
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                missing_packages+=("$pkg")
            fi
        elif command -v rpm >/dev/null 2>&1; then
            # RPM-based distro check
            if ! rpm -q "$pkg" >/dev/null 2>&1; then
                missing_packages+=("$pkg")
            fi
        elif command -v pacman >/dev/null 2>&1; then
            # Arch-based check
            if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
                missing_packages+=("$pkg")
            fi
        else
            # Fallback: check if command exists
            log_warn "Package manager not recognized, checking for binary: $pkg"
            if ! command -v "$pkg" >/dev/null 2>&1; then
                missing_packages+=("$pkg")
            fi
        fi
    done

    # Second pass: install missing packages
    if [ ${#missing_packages[@]} -gt 0 ]; then
        if [[ "$interactive" == "true" ]]; then
            log_info "Installing missing packages: ${missing_packages[*]}"
            
            # Install packages based on detected package manager
            if command -v apt >/dev/null 2>&1; then
                apt install -y "${missing_packages[@]}" || {
                    log_warn "Some packages failed to install from repository"
                    handle_package_fallbacks
                }
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y "${missing_packages[@]}" || {
                    log_warn "Some packages failed to install from repository"
                    handle_package_fallbacks
                }
            elif command -v pacman >/dev/null 2>&1; then
                pacman -S --noconfirm "${missing_packages[@]}" || {
                    log_warn "Some packages failed to install from repository"
                    handle_package_fallbacks
                }
            else
                log_warn "No supported package manager found for automatic installation"
                handle_package_fallbacks
            fi
        else
            log_warn "Non-interactive mode detected, skipping package installation"
            log_warn "Missing packages: ${missing_packages[*]}"
            log_info "Please install these packages manually or run in interactive mode"
            return 1
        fi
    fi

    # Verify critical commands
    verify_critical_commands || return 1
    
    # Verify and select boot image tools
    verify_boot_image_tools || return 1
    
    # Check for compiler/cross-compiler
    verify_compiler || return 1
    
    log_success "All dependencies installed and verified"
    return 0
}

# Handle fallback installation for critical packages
handle_package_fallbacks() {
    # Try manual installation for critical boot image tools
    if [[ " ${missing_packages[*]} " =~ " abootimg " ]]; then
        log_info "Attempting manual abootimg installation..."
        if ! command -v abootimg >/dev/null 2>&1; then
            local tmp_dir="$(mktemp -d)"
            TEMP_FILES+=("$tmp_dir")
            cd "$tmp_dir"
            git clone https://github.com/ggrandou/abootimg.git
            cd abootimg
            make && {
                cp abootimg /usr/local/bin/ || {
                    log_warn "Failed to install abootimg to /usr/local/bin"
                    mkdir -p "$SCRIPT_DIR/bin"
                    cp abootimg "$SCRIPT_DIR/bin/" && {
                        chmod +x "$SCRIPT_DIR/bin/abootimg"
                        export PATH="$SCRIPT_DIR/bin:$PATH"
                        log_info "Installed abootimg to $SCRIPT_DIR/bin"
                    }
                }
            }
            cd / && rm -rf "$tmp_dir"
        fi
    fi
    
    if [[ " ${missing_packages[*]} " =~ " android-tools-mkbootimg " || " ${missing_packages[*]} " =~ " mkbootimg " ]]; then
        log_info "Attempting mkbootimg installation via pip..."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install mkbootimg || pip3 install --user mkbootimg
        elif command -v pip >/dev/null 2>&1; then
            pip install mkbootimg || pip install --user mkbootimg
        else
            log_warn "Python pip not available, cannot install mkbootimg via pip"
        fi
    fi
}

# Verify critical commands are available
verify_critical_commands() {
    local missing_commands=()
    for cmd in "${CRITICAL_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Critical commands missing after installation: ${missing_commands[*]}"
        log_info "Please install these commands manually or check your PATH"
        return 1
    fi
    
    return 0
}

# Verify boot image tools are available
verify_boot_image_tools() {
    # Check for boot image tools (at least one must be available, prefer abootimg)
    local boot_tools=("abootimg" "mkbootimg")
    local boot_tool_available=false
    local working_tool=""
    
    # Check abootimg first (preferred)
    if command -v abootimg >/dev/null 2>&1; then
        boot_tool_available=true
        working_tool="abootimg"
        export BOOT_TOOL="abootimg"
        log_success "Boot image tool available: abootimg (preferred)"
    elif command -v mkbootimg >/dev/null 2>&1; then
        # Test if mkbootimg actually works
        if mkbootimg --help >/dev/null 2>&1; then
            boot_tool_available=true
            working_tool="mkbootimg"
            export BOOT_TOOL="mkbootimg" 
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
    
    # Store the selected boot tool for global use
    export BOOT_IMAGE_TOOL="$working_tool"
    return 0
}

# Verify compiler is available
verify_compiler() {
    # Check cross-compiler
    local cross_compiler="${CROSS_COMPILE}gcc"
    if ! command -v "$cross_compiler" >/dev/null 2>&1; then
        log_warn "Cross-compiler not found: $cross_compiler"
        log_info "Checking for generic compiler..."
        
        if command -v gcc >/dev/null 2>&1; then
            log_warn "Using native gcc instead of cross-compiler"
            log_warn "This may cause compatibility issues with the target device"
            # Allow override for testing purposes
            if [[ "${ALLOW_NATIVE_COMPILER:-false}" == "true" ]]; then
                log_info "ALLOW_NATIVE_COMPILER is set, continuing with native gcc"
                export CROSS_COMPILE=""
            else
                log_error "Cross-compiler is required for proper ARM64 builds"
                log_info "Please install: gcc-aarch64-linux-gnu package"
                return 1
            fi
        else
            log_error "No compiler found! Cannot continue."
            return 1
        fi
    else
        log_debug "Cross-compiler found: $cross_compiler"
    fi
    
    return 0
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
    
    # Validate required directories are defined
    if [[ -z "${BUILD_DIR:-}" ]]; then
        log_error "BUILD_DIR not defined! Check constants.sh"
        return 1
    fi
    
    if [[ -z "${OUTPUT_DIR:-}" ]]; then
        log_warn "OUTPUT_DIR not defined, defaulting to ./output"
        export OUTPUT_DIR="$(pwd)/output"
    fi
    
    if [[ -z "${TEMP_BUILD_DIR:-}" ]]; then
        log_warn "TEMP_BUILD_DIR not defined, defaulting to /tmp/rg35xx_build"
        export TEMP_BUILD_DIR="/tmp/rg35xx_build"
    fi
    
    # Create required directory structure
    mkdir -p "$BUILD_DIR"/{busybox,rootfs,kernel} || {
        log_error "Failed to create build directories"
        return 1
    }
    
    mkdir -p "$OUTPUT_DIR" || {
        log_error "Failed to create output directory: $OUTPUT_DIR"
        return 1
    }
    
    # Check write permissions for critical directories
    if [[ ! -w "$OUTPUT_DIR" ]]; then
        log_error "Cannot write to output directory: $OUTPUT_DIR"
        log_error "Try: sudo chown $(whoami) $OUTPUT_DIR"
        return 1
    fi
    
    mkdir -p "$TEMP_BUILD_DIR" || {
        log_warn "Failed to create temp directory, trying alternative location"
        export TEMP_BUILD_DIR="/tmp/rg35xx_build_alt"
        mkdir -p "$TEMP_BUILD_DIR" || {
            log_error "Failed to create any temp build directory"
            return 1
        }
    }
    
    # Setup ccache for faster rebuilds
    setup_ccache
    
    # Display build configuration
    log_info "Build directory: $BUILD_DIR"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Temp directory: $TEMP_BUILD_DIR"
    
    # Check if linux directory exists
    if [[ -d "$BUILD_DIR/linux" ]]; then
        log_info "Found existing Linux source directory"
        
        # Check if git is initialized in the Linux directory
        if [[ -d "$BUILD_DIR/linux/.git" ]]; then
            log_info "Linux source is git-managed (can pull updates)"
        else
            log_info "Linux source is not git-managed (static copy)"
        fi
    fi
    
    log_success "Build environment successfully configured"
}

setup_ccache() {
    if command -v ccache >/dev/null 2>&1; then
        # Use configured cache dir from constants or fallback to default
        export CCACHE_DIR="${CCACHE_DIR:-/tmp/ccache}"
        export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-4G}"
        export CCACHE_COMPRESS="true"
        
        # Create cache directory if it doesn't exist
        mkdir -p "$CCACHE_DIR" || {
            log_warn "Failed to create ccache directory: $CCACHE_DIR"
            log_warn "Using default ccache location"
            unset CCACHE_DIR
        }
        
        # Check if original CROSS_COMPILE already has ccache
        if [[ "${CROSS_COMPILE:-}" != *"ccache"* ]]; then
            # Setup ccache for cross compiler only if not already set
            export CROSS_COMPILE="ccache ${CROSS_COMPILE:-aarch64-linux-gnu-}"
        fi
        
        # Add ccache directory to PATH if not already there
        if [[ ":$PATH:" != *":/usr/lib/ccache:"* ]]; then
            export PATH="/usr/lib/ccache:$PATH"
        fi
        
        log_info "ccache enabled with ${CCACHE_MAXSIZE} cache at ${CCACHE_DIR}"
        
        # Check ccache stats
        if ccache -s &>/dev/null; then
            log_debug "ccache stats: $(ccache -s | grep -E 'cache hit|cache miss' | tr '\n' ' ')"
        fi
    else
        log_warn "ccache not available, builds will be slower"
        log_info "Consider installing ccache for faster rebuilds"
    fi
}

cleanup_build() {
    log_step "Cleaning build directories"
    
    if [[ -z "${BUILD_DIR:-}" ]]; then
        log_error "BUILD_DIR not defined. Cannot clean up."
        return 1
    fi
    
    # Ask for confirmation if BUILD_DIR is at a dangerous location
    if [[ "$BUILD_DIR" == "/" || "$BUILD_DIR" == "/home" || "$BUILD_DIR" == "/usr" || "$BUILD_DIR" == "$HOME" ]]; then
        log_error "Refusing to delete sensitive directory: $BUILD_DIR"
        return 1
    fi
    
    # Clean temporary files first
    if [[ -n "${TEMP_BUILD_DIR:-}" && -d "$TEMP_BUILD_DIR" ]]; then
        log_info "Cleaning temporary build directory: $TEMP_BUILD_DIR"
        rm -rf "$TEMP_BUILD_DIR" 2>/dev/null || {
            log_warn "Failed to clean temporary build directory. You may need to manually delete it."
        }
    fi
    
    # Clean build directory if specified
    if [[ "$FORCE_REBUILD" == true ]]; then
        log_warn "Force rebuild enabled - cleaning main build directory: $BUILD_DIR"
        rm -rf "$BUILD_DIR"/* 2>/dev/null || {
            log_warn "Failed to completely clean build directory. You may need to manually delete it."
        }
    else
        log_info "Cleaning object files and temporary build artifacts"
        find "$BUILD_DIR" -name "*.o" -delete 2>/dev/null || true
        find "$BUILD_DIR" -name "*.ko" -delete 2>/dev/null || true
        find "$BUILD_DIR" -name "*.cmd" -delete 2>/dev/null || true
    fi
    
    log_success "Build cleanup completed"
}
