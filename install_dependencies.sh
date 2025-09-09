#!/bin/bash
# Install dependencies for RG35XX_H custom build environment

source "$(dirname "${BASH_SOURCE[0]}")/lib/logger.sh"

install_build_dependencies() {
    log_info "Installing build dependencies..."
    
    # Update package lists
    log_info "Updating package lists..."
    apt-get update || {
        log_error "Failed to update package lists"
        return 1
    }
    
    # Essential build tools
    log_info "Installing essential build tools..."
    apt-get install -y \
        build-essential \
        gcc-aarch64-linux-gnu \
        git \
        bc \
        bison \
        flex \
        libssl-dev \
        libncurses5-dev \
        libelf-dev \
        kmod \
        cpio \
        rsync \
        curl \
        wget \
        unzip \
        python3 \
        python3-pip || {
        log_error "Failed to install essential build tools"
        return 1
    }
    
    # Boot image tools - critical for RG35XX_H (prefer abootimg over mkbootimg)
    log_info "Installing boot image tools..."
    
    # Install abootimg first (more reliable than android-tools-mkbootimg)
    if apt-get install -y abootimg device-tree-compiler; then
        log_success "abootimg and dtc installed successfully"
    else
        log_warn "abootimg package installation failed, trying manual compilation..."
        
        # Manual abootimg installation
        log_info "Compiling abootimg from source..."
        cd /tmp
        git clone https://github.com/ggrandou/abootimg.git
        cd abootimg
        if make && cp abootimg /usr/local/bin/; then
            log_success "abootimg compiled and installed manually"
        else
            log_error "abootimg manual compilation failed"
        fi
        cd /
        rm -rf /tmp/abootimg
    fi
    
    # Try android-tools as secondary option (but it may have gki module issues)
    if ! command -v abootimg >/dev/null 2>&1; then
        log_info "Trying android-tools-mkbootimg as fallback..."
        apt-get install -y android-tools-mkbootimg android-tools-fsutils || {
            log_warn "Android tools package installation failed"
            
            # Try pip installation as last resort
            log_info "Trying pip3 mkbootimg installation..."
            pip3 install mkbootimg || {
                log_warn "pip3 mkbootimg installation also failed"
            }
        }
    fi
    
    # Verify critical tools
    log_info "Verifying critical tools..."
    local missing_tools=()
    
    command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || missing_tools+=("aarch64-linux-gnu-gcc")
    command -v git >/dev/null 2>&1 || missing_tools+=("git")
    command -v make >/dev/null 2>&1 || missing_tools+=("make")
    command -v dtc >/dev/null 2>&1 || missing_tools+=("dtc")
    
    # Boot image tools (at least one should be available, prefer abootimg)
    if command -v abootimg >/dev/null 2>&1; then
        log_success "✅ abootimg available (preferred tool)"
    elif command -v mkbootimg >/dev/null 2>&1; then
        # Test if mkbootimg actually works
        if mkbootimg --help >/dev/null 2>&1; then
            log_success "✅ mkbootimg available (may have dependency issues)"
        else
            log_warn "⚠️ mkbootimg found but not working (gki module issues)"
            missing_tools+=("working-boot-image-tools")
        fi
    else
        missing_tools+=("boot-image-tools")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing critical tools: ${missing_tools[*]}"
        return 1
    fi
    
    log_success "All dependencies installed successfully!"
    
    # Show tool versions
    log_info "Tool versions:"
    echo "  GCC: $(aarch64-linux-gnu-gcc --version | head -1)"
    echo "  Git: $(git --version)"
    echo "  Make: $(make --version | head -1)"
    echo "  DTC: $(dtc --version 2>&1 | head -1)"
    
    if command -v abootimg >/dev/null 2>&1; then
        echo "  abootimg: available"
    fi
    if command -v mkbootimg >/dev/null 2>&1; then
        echo "  mkbootimg: available"
    fi
    
    return 0
}

check_dependencies() {
    log_info "Checking build dependencies..."
    
    local missing=()
    local warnings=()
    
    # Critical tools
    command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || missing+=("aarch64-linux-gnu-gcc")
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v make >/dev/null 2>&1 || missing+=("make")
    command -v dtc >/dev/null 2>&1 || missing+=("dtc")
    
    # Boot image tools (at least one required)
    if ! command -v abootimg >/dev/null 2>&1 && ! command -v mkbootimg >/dev/null 2>&1; then
        missing+=("boot-image-tools (abootimg or mkbootimg)")
    fi
    
    # Useful but not critical
    command -v curl >/dev/null 2>&1 || warnings+=("curl")
    command -v wget >/dev/null 2>&1 || warnings+=("wget")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies:"
        for tool in "${missing[@]}"; do
            echo "  - $tool"
        done
        log_info "Run: sudo $0 install"
        return 1
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "Missing optional tools:"
        for tool in "${warnings[@]}"; do
            echo "  - $tool"
        done
    fi
    
    log_success "All required dependencies are available!"
    return 0
}

show_help() {
    echo "RG35XX_H Custom Build - Dependency Installer"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install    Install all build dependencies"
    echo "  check      Check if dependencies are installed"
    echo "  help       Show this help message"
    echo ""
    echo "This script installs the tools needed to build custom kernels"
    echo "for the RG35XX_H handheld gaming device."
}

main() {
    case "${1:-check}" in
        install)
            if [[ $EUID -ne 0 ]]; then
                log_error "Installation requires root privileges"
                log_info "Run: sudo $0 install"
                exit 1
            fi
            install_build_dependencies
            ;;
        check)
            check_dependencies
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
