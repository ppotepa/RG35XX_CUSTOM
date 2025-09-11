#!/bin/bash
# Centralized kernel builder module for RG35XX-H

# Guard against multiple sourcing
[[ -n "${RG35XX_KERNEL_BUILDER_LOADED:-}" ]] && return 0
export RG35XX_KERNEL_BUILDER_LOADED=1

# Import required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/constants.sh"
source "$SCRIPT_DIR/lib/logger.sh"
source "$SCRIPT_DIR/lib/system.sh"

#####################################################
# KERNEL BUILD CONFIGURATION
#####################################################

# Default kernel settings - can be overridden
: ${KERNEL_REPO:="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"}
: ${KERNEL_BRANCH:="linux-6.10.y"}
: ${KERNEL_DIR:="$BUILD_DIR/linux"}
: ${KERNEL_OUT_DIR:="$BUILD_DIR/linux_out"}
: ${ARCH:="arm64"}
: ${CROSS_COMPILE:="aarch64-linux-gnu-"}
: ${MAKE_FLAGS:="-j$(nproc)"}

# Kernel configuration options for RG35XX-H
declare -A KERNEL_CONFIG_OPTIONS=(
    ["CONFIG_FB_SIMPLE"]="y"                   # Simple framebuffer driver
    ["CONFIG_FRAMEBUFFER_CONSOLE"]="y"         # Enable framebuffer console
    ["CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY"]="y"  # Auto-detect primary framebuffer
    ["CONFIG_LOGO"]="y"                        # Show logo on boot
    ["CONFIG_BACKLIGHT_CLASS_DEVICE"]="y"      # Backlight support
    ["CONFIG_VT_CONSOLE_SLEEP"]="n"            # Disable deferred console takeover
    ["CONFIG_CMDLINE_FORCE"]="y"               # Force kernel command line
)

#####################################################
# KERNEL BUILDING FUNCTIONS
#####################################################

# Clone or update kernel repository
kernel_clone() {
    log_step "Preparing kernel source code"
    
    # Check if kernel directory already exists
    if [[ -d "$KERNEL_DIR/.git" ]]; then
        log_info "Kernel source already exists at $KERNEL_DIR"
        
        if [[ "$FORCE_REBUILD" == "true" ]]; then
            log_warn "Force rebuild enabled - Cleaning kernel source"
            cd "$KERNEL_DIR" || { log_error "Failed to enter kernel directory"; return 1; }
            git clean -fdx
            git reset --hard
        fi
        
        # Try to checkout the specified branch
        cd "$KERNEL_DIR" || { log_error "Failed to enter kernel directory"; return 1; }
        if ! git checkout "$KERNEL_BRANCH" &>/dev/null; then
            log_warn "Failed to checkout branch $KERNEL_BRANCH, trying to fetch updates"
            git fetch --depth 1 origin "$KERNEL_BRANCH" || { 
                log_error "Failed to fetch branch $KERNEL_BRANCH"
                return 1
            }
            git checkout "$KERNEL_BRANCH" || {
                log_error "Failed to checkout branch $KERNEL_BRANCH"
                return 1
            }
        fi
        
        log_success "Kernel source ready: $KERNEL_DIR (branch: $KERNEL_BRANCH)"
    else
        # Clone the repository
        log_info "Cloning kernel from $KERNEL_REPO (branch: $KERNEL_BRANCH)"
        mkdir -p "$(dirname "$KERNEL_DIR")" || { log_error "Failed to create parent directory"; return 1; }
        
        git clone --branch "$KERNEL_BRANCH" --depth 1 "$KERNEL_REPO" "$KERNEL_DIR" || {
            log_error "Failed to clone kernel repository"
            return 1
        }
        
        log_success "Kernel source cloned successfully: $KERNEL_DIR"
    fi
    
    return 0
}

# Create and customize kernel config
kernel_configure() {
    log_step "Configuring kernel for RG35XX-H"
    
    cd "$KERNEL_DIR" || { log_error "Failed to enter kernel directory"; return 1; }
    
    # Create kernel output directory if it doesn't exist
    mkdir -p "$KERNEL_OUT_DIR" || { log_error "Failed to create kernel output directory"; return 1; }
    
    # Start with defconfig
    log_info "Creating base configuration with defconfig"
    make O="$KERNEL_OUT_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig || {
        log_error "Failed to create defconfig"
        return 1
    }
    
    # Apply custom configuration options
    log_info "Applying RG35XX-H specific configuration options"
    
    # Create a temporary script to modify the .config file
    local config_script=$(mktemp)
    echo '#!/bin/bash' > "$config_script"
    echo 'CONFIG_FILE="$1"' >> "$config_script"
    
    # Add each configuration option
    for option in "${!KERNEL_CONFIG_OPTIONS[@]}"; do
        local value="${KERNEL_CONFIG_OPTIONS[$option]}"
        echo "sed -i 's/^# $option is not set/$option=$value/' \"\$CONFIG_FILE\" || true" >> "$config_script"
        echo "if ! grep -q \"^$option=$value\" \"\$CONFIG_FILE\"; then echo \"$option=$value\" >> \"\$CONFIG_FILE\"; fi" >> "$config_script"
    done
    
    # Make script executable
    chmod +x "$config_script"
    
    # Run the script to modify .config
    "$config_script" "$KERNEL_OUT_DIR/.config" || {
        log_error "Failed to apply custom configuration"
        rm -f "$config_script"
        return 1
    }
    
    # Clean up
    rm -f "$config_script"
    
    # Add kernel command line from constants
    if [[ -n "${KERNEL_CMDLINE:-}" ]]; then
        log_info "Setting kernel command line: $KERNEL_CMDLINE"
        sed -i "s|^CONFIG_CMDLINE=.*|CONFIG_CMDLINE=\"$KERNEL_CMDLINE\"|" "$KERNEL_OUT_DIR/.config" || true
        if ! grep -q "^CONFIG_CMDLINE=" "$KERNEL_OUT_DIR/.config"; then
            echo "CONFIG_CMDLINE=\"$KERNEL_CMDLINE\"" >> "$KERNEL_OUT_DIR/.config"
        fi
    fi
    
    # Regenerate final config
    make O="$KERNEL_OUT_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig || {
        log_error "Failed to regenerate config"
        return 1
    }
    
    log_success "Kernel configured successfully for RG35XX-H"
    return 0
}

# Build the kernel
kernel_build() {
    log_step "Building kernel for RG35XX-H"
    
    cd "$KERNEL_DIR" || { log_error "Failed to enter kernel directory"; return 1; }
    
    # Build kernel image
    log_info "Building kernel image (this may take a while)"
    make O="$KERNEL_OUT_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" $MAKE_FLAGS Image || {
        log_error "Failed to build kernel image"
        return 1
    }
    
    # Build device tree blobs
    log_info "Building device tree blobs"
    make O="$KERNEL_OUT_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" $MAKE_FLAGS dtbs || {
        log_error "Failed to build device tree blobs"
        return 1
    }
    
    # Check if the files were generated
    if [[ ! -f "$KERNEL_OUT_DIR/arch/$ARCH/boot/Image" ]]; then
        log_error "Kernel Image not found after build"
        return 1
    fi
    
    # Copy output files to output directory
    mkdir -p "$OUTPUT_DIR" || { log_error "Failed to create output directory"; return 1; }
    cp "$KERNEL_OUT_DIR/arch/$ARCH/boot/Image" "$OUTPUT_DIR/" || {
        log_error "Failed to copy kernel Image to output directory"
        return 1
    }
    
    # Copy RG35XX-H specific DTB
    if [[ -f "$KERNEL_OUT_DIR/arch/$ARCH/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-h.dtb" ]]; then
        cp "$KERNEL_OUT_DIR/arch/$ARCH/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-h.dtb" "$OUTPUT_DIR/" || {
            log_error "Failed to copy RG35XX-H DTB to output directory"
            return 1
        }
    else
        log_warn "RG35XX-H DTB not found, looking for generic sun50i-h700 DTB"
        # Try to find any H700 DTB as fallback
        find "$KERNEL_OUT_DIR/arch/$ARCH/boot/dts" -name "sun50i-h700*.dtb" -exec cp {} "$OUTPUT_DIR/" \; || {
            log_error "Failed to find any compatible DTB"
            return 1
        }
    fi
    
    log_success "Kernel build completed successfully"
    log_info "Output files:"
    log_info " - Kernel Image: $OUTPUT_DIR/Image"
    log_info " - Device Tree: $OUTPUT_DIR/*.dtb"
    
    return 0
}

# Complete kernel build process
build_kernel_complete() {
    # Perform kernel build steps in sequence
    kernel_clone || return 1
    kernel_configure || return 1
    kernel_build || return 1
    
    log_success "Kernel build process completed successfully"
    return 0
}

# Export functions
export -f kernel_clone
export -f kernel_configure
export -f kernel_build
export -f build_kernel_complete
