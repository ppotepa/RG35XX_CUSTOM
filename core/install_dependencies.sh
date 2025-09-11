#!/bin/bash
# Install dependencies for RG35XX_H custom build environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/logger.sh"

has_apt_candidate() {
    local pkg="$1"
    apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -vq '(none)'
}

ensure_local_mkbootimg_with_venv() {
    # Create local venv and install mkbootimg, then symlink to /usr/local/bin
    local venv_dir="$SCRIPT_DIR/.venv-tools"
    if [[ ! -d "$venv_dir" ]]; then
        log_info "Creating local Python venv for mkbootimg..."
        apt-get install -y python3-venv || {
            log_warn "python3-venv not available; cannot create local venv"
            return 1
        }
        python3 -m venv "$venv_dir" || return 1
    fi
    log_info "Installing mkbootimg into local venv..."
    "$venv_dir/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
    "$venv_dir/bin/pip" install mkbootimg || {
        log_warn "Failed to install mkbootimg into venv"
        return 1
    }
    # Expose mkbootimg globally for this host
    if [[ -x "$venv_dir/bin/mkbootimg" ]]; then
        ln -sf "$venv_dir/bin/mkbootimg" /usr/local/bin/mkbootimg 2>/dev/null || true
        log_success "mkbootimg available via local venv"
        return 0
    fi
    return 1
}

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
    
    # Try mkbootimg as secondary option
    if ! command -v mkbootimg >/dev/null 2>&1; then
        log_info "Checking mkbootimg apt packages availability..."
        local tried_pkg=0
        if has_apt_candidate android-tools-mkbootimg; then
            apt-get install -y android-tools-mkbootimg && tried_pkg=1 || log_warn "Failed to install android-tools-mkbootimg"
        else
            log_warn "Package 'android-tools-mkbootimg' has no installation candidate"
        fi
        if has_apt_candidate android-tools-fsutils; then
            apt-get install -y android-tools-fsutils || log_warn "Failed to install android-tools-fsutils"
        else
            log_warn "Package 'android-tools-fsutils' has no installation candidate"
        fi

        # If still no mkbootimg, try pipx then venv
        if ! command -v mkbootimg >/dev/null 2>&1; then
            log_info "Attempting mkbootimg installation via pipx (preferred for PEP 668)..."
            if has_apt_candidate pipx; then
                apt-get install -y pipx || log_warn "pipx installation failed"
            else
                apt-get install -y pipx || true
            fi
            if command -v pipx >/dev/null 2>&1; then
                pipx install mkbootimg || log_warn "pipx mkbootimg install failed"
                # pipx installs to ~/.local/bin
                if [[ -x "/root/.local/bin/mkbootimg" ]]; then
                    ln -sf "/root/.local/bin/mkbootimg" /usr/local/bin/mkbootimg 2>/dev/null || true
                fi
            fi
        fi

        # Venv fallback for externally-managed environment
        if ! command -v mkbootimg >/dev/null 2>&1; then
            log_info "pip is externally-managed; creating local venv for mkbootimg..."
            ensure_local_mkbootimg_with_venv || log_warn "Local venv installation failed"
        fi

        if ! command -v mkbootimg >/dev/null 2>&1; then
            log_warn "mkbootimg is still unavailable. We'll rely on abootimg path."
            log_warn "If you need mkbootimg, enable appropriate apt repos or use a venv."
        else
            log_success "mkbootimg is available"
        fi
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
    echo "Tips:"
    echo "  - Prefer 'abootimg' (apt install abootimg)"
    echo "  - If 'android-tools-mkbootimg' has no candidate, use a local venv:"
    echo "      sudo apt-get install -y python3-venv && \"
    echo "      python3 -m venv $SCRIPT_DIR/.venv-tools && \"
    echo "      $SCRIPT_DIR/.venv-tools/bin/pip install mkbootimg && \"
    echo "      ln -s $SCRIPT_DIR/.venv-tools/bin/mkbootimg /usr/local/bin/mkbootimg"
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

