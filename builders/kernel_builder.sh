#!/bin/bash
# Kernel building functionality

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

get_linux_source() {
    step "Getting Linux kernel source"
    
    if [[ ! -d "$SCRIPT_DIR/linux" ]]; then
        log "Cloning Linux kernel..."
        git clone --depth=1 --branch "$LINUX_BRANCH" \
            https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
            "$SCRIPT_DIR/linux"
    else
        log "Using existing Linux source"
    fi
    
    log "Copying source to build directory..."
    rsync -a --exclude='.git' "$SCRIPT_DIR/linux/" "$BUILD_DIR/linux/"
}

download_device_tree() {
    local target_dir="$1"
    
    log "Downloading device tree files..."
    mkdir -p "$target_dir"
    
    for file in "$RG35XX_DTS" "$H616_DTSI"; do
        if [[ ! -f "$target_dir/$file" ]]; then
            if command -v curl >/dev/null 2>&1; then
                curl -s -o "$target_dir/$file" "$DEVICE_TREE_URL/$file"
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$target_dir/$file" "$DEVICE_TREE_URL/$file"
            else
                warn "Neither curl nor wget available, cannot download device tree"
                return 1
            fi
        fi
    done
}

configure_kernel() {
    step "Configuring kernel"
    cd "$BUILD_DIR/linux"
    
    log "Creating base config..."
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" defconfig
    
    # Ensure device tree source is available
    local dts_dir="arch/arm64/boot/dts/allwinner"
    if [[ ! -f "$dts_dir/$RG35XX_DTS" ]]; then
        log "Device tree source not found, downloading..."
        download_device_tree "$dts_dir" || warn "Failed to download device tree"
    fi

    # Apply custom configuration
    apply_custom_config
    
    log "Resolving configuration dependencies..."
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
}

apply_custom_config() {
    if [[ ! -f "$SCRIPT_DIR/config_patch" ]]; then
        warn "No config_patch found, using default configuration"
        return
    fi

    log "Applying custom configuration..."
    local temp_config="/tmp/rg35xx_config_$$"
    
    # Clean and convert config_patch
    sed 's/\r$//' "$SCRIPT_DIR/config_patch" | \
    grep -E '^CONFIG_[A-Z0-9_]+=' > "$temp_config"
    
    if scripts/kconfig/merge_config.sh .config "$temp_config"; then
        log "Configuration merged successfully"
    else
        warn "merge_config.sh failed, trying fallback method..."
        apply_config_fallback "$temp_config"
    fi
    
    rm -f "$temp_config"
}

apply_config_fallback() {
    local config_file="$1"
    
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^CONFIG_[A-Z0-9_]+$ ]] || continue
        [[ -n "$val" ]] || continue
        
        case "$val" in
            y|Y) scripts/config --enable "$key" ;;
            n|N) scripts/config --disable "$key" ;;
            m|M) scripts/config --module "$key" ;;
            [0-9]*) scripts/config --set-val "$key" "$val" ;;
            \"*\")
                clean_val="${val%\"}"
                clean_val="${clean_val#\"}"
                scripts/config --set-str "$key" "$clean_val"
                ;;
        esac
    done < "$config_file"
}

build_kernel() {
    step "Building kernel"
    cd "$BUILD_DIR/linux"
    
    local nproc=$(nproc)
    log "Building with $nproc parallel jobs..."
    
    log "Building kernel Image..."
    make -j"$nproc" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" Image
    
    log "Building device trees..."
    make -j"$nproc" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" dtbs
    
    log "Building kernel modules..."
    make -j"$nproc" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules
    
    create_kernel_image
    install_kernel_modules
}

create_kernel_image() {
    local dtb_file=""
    local dts_path="arch/arm64/boot/dts/allwinner"
    
    # Find appropriate DTB
    if [[ -f "$dts_path/sun50i-h700-anbernic-rg35xx-h.dtb" ]]; then
        dtb_file="$dts_path/sun50i-h700-anbernic-rg35xx-h.dtb"
        log "Found exact DTB match for RG35XX_H"
    else
        dtb_file=$(find arch/arm64/boot/dts -name '*rg35xx*h*.dtb' -o -name '*h700*.dtb' -o -name '*h616*.dtb' | grep -v "overlay" | head -1)
    fi
    
    [[ -f "$dtb_file" ]] || error "No suitable device tree found"
    
    log "Using DTB: $dtb_file"
    
    # Create combined kernel+dtb
    cp arch/arm64/boot/Image "$BUILD_DIR/out/"
    cp "$dtb_file" "$BUILD_DIR/out/dtb"
    cat "$BUILD_DIR/out/Image" "$BUILD_DIR/out/dtb" > "$BUILD_DIR/out/zImage-dtb"
}

install_kernel_modules() {
    log "Installing kernel modules..."
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
         INSTALL_MOD_PATH="$BUILD_DIR/rootfs" modules_install
}
