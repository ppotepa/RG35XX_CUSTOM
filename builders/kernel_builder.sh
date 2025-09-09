#!/bin/bash
# Kernel building functionality

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

get_linux_source() {
    log_step "Getting Linux kernel source"
    update_progress "kernel" 0 "Preparing kernel source..."
    
    if [[ ! -d "$BUILD_DIR/linux" ]]; then
        log_info "Cloning Linux kernel..."
        update_progress "kernel" 5 "Cloning kernel repository..."
        git clone --depth=1 --branch "$LINUX_BRANCH" \
            https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
            "$BUILD_DIR/linux" 2>&1 | while read -r line; do
                if [[ "$line" =~ ([0-9]+)% ]]; then
                    local percent="${BASH_REMATCH[1]}"
                    update_progress "kernel" $((5 + percent / 4)) "Cloning: ${percent}%"
                fi
            done
        update_progress "kernel" 30 "Kernel source ready"
    else
        log_info "Using existing Linux source at $BUILD_DIR/linux"
        update_progress "kernel" 30 "Using existing source"
        # Quick update for faster builds
        cd "$BUILD_DIR/linux"
        git fetch --depth=1 origin "$LINUX_BRANCH" 2>/dev/null || log_warn "Could not update source"
        git reset --hard FETCH_HEAD 2>/dev/null || log_warn "Could not reset to latest"
    fi
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
    
    # Ensure device tree sources are available for all variants
    local dts_dir="arch/arm64/boot/dts/allwinner"
    for dtb in "${DTB_VARIANTS[@]}"; do
        local dts_file="${dtb%.dtb}.dts"
        if [[ ! -f "$dts_dir/$dts_file" ]]; then
            log "Device tree source for $dtb not found, downloading..."
            download_device_tree "$dts_dir" "$dts_file" || warn "Failed to download device tree"
        fi
    done

    # Apply custom configuration
    apply_custom_config
    
    # Force cmdline settings for guaranteed console output
    log "Forcing console cmdline settings..."
    echo "CONFIG_CMDLINE=\"console=tty0 loglevel=7 ignore_loglevel\"" >> .config
    echo "CONFIG_CMDLINE_BOOL=y" >> .config
    echo "CONFIG_CMDLINE_FORCE=y" >> .config
    
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
    log_step "Building kernel"
    start_progress "kernel" 100
    cd "$BUILD_DIR/linux"
    
    log_info "Building with $BUILD_JOBS parallel jobs (CPU cores: $MAX_CORES)..."
    
    update_progress 10 "Building kernel Image..."
    # Use aggressive optimization for speed
    make -j"$BUILD_JOBS" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
         KCFLAGS="-O3 -march=native -mtune=native -pipe" \
         Image 2>&1 | while IFS= read -r line; do
        if [[ "$line" =~ CC[[:space:]]+([^[:space:]]+) ]]; then
            # Update progress occasionally to avoid spam
            if ((RANDOM % 20 == 0)); then
                update_progress $((10 + RANDOM % 30)) "Compiling kernel... $(basename "${BASH_REMATCH[1]}")"
            fi
        elif [[ "$line" =~ LD[[:space:]]+vmlinux ]]; then
            update_progress 35 "Linking vmlinux..."
        fi
    done
    log_success "Kernel Image build completed"
    
    update_progress 45 "Building device trees..."
    make -j"$BUILD_JOBS" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" dtbs >/dev/null 2>&1
    log_success "Device trees build completed"
    
    update_progress 60 "Building kernel modules..."
    make -j"$BUILD_JOBS" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules 2>&1 | \
    while IFS= read -r line; do
        if [[ "$line" =~ LD[[:space:]]+\[M\][[:space:]]+([^[:space:]]+) ]]; then
            if ((RANDOM % 10 == 0)); then
                update_progress $((60 + RANDOM % 20)) "Building module... $(basename "${BASH_REMATCH[1]}")"
            fi
        fi
    done
    log_success "Kernel modules build completed"
    
    update_progress 85 "Creating kernel image..."
    create_kernel_image
    
    update_progress 95 "Installing kernel modules..."
    install_kernel_modules
    
    update_progress 100 "Kernel build complete"
    end_progress "Kernel built successfully"
    log_success "Kernel build phase completed successfully"
}

create_kernel_image() {
    log_info "Creating kernel boot images with multiple DTB variants..."
    local dts_path="arch/arm64/boot/dts/allwinner"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR/dtbs"
    
    # Copy the kernel Image
    cp arch/arm64/boot/Image "$OUTPUT_DIR/"
    
    # Process all DTB variants
    for dtb_name in "${DTB_VARIANTS[@]}"; do
        local dtb_file="$dts_path/$dtb_name"
        
        if [[ -f "$dtb_file" ]]; then
            log_info "Processing DTB: $dtb_name"
            
            # Copy individual DTB
            cp "$dtb_file" "$OUTPUT_DIR/dtbs/"
            
            # Create combined images for each DTB variant
            if [[ "$ACTIVE_DTB" == "$dtb_name" ]]; then
                log_info "Setting $dtb_name as active DTB"
                cp "$dtb_file" "$OUTPUT_DIR/dtb"
                cat "$OUTPUT_DIR/Image" "$OUTPUT_DIR/dtb" > "$OUTPUT_DIR/zImage-dtb"
                
                # Create a dtb.img for with-dt mode
                cp "$dtb_file" "$OUTPUT_DIR/dtb.img"
            fi
        else
            log_warn "DTB variant not found: $dtb_file"
        fi
    done
    
    # Also create a concatenated DTB image with all variants
    log_info "Creating combined DTB image with all variants..."
    cat $dts_path/sun50i-h700-*.dtb > "$OUTPUT_DIR/dtb-all.img"
    
    # Package boot images for both modes
    package_boot_images
    
    local size=$(stat -c%s "$OUTPUT_DIR/zImage-dtb" | numfmt --to=iec)
    log_success "Created zImage-dtb ($size)"
}

package_boot_images() {
    log_info "Creating boot images for both packaging modes..."
    
    # Check for stock boot image to extract ramdisk
    local stock_boot="/tmp/boot-stock.img"
    local ramdisk="/tmp/ramdisk.img"
    
    if [[ ! -f "$ramdisk" ]]; then
        log_warn "Stock ramdisk not found. Will create a minimal ramdisk."
        # Create minimal empty ramdisk if needed
        mkdir -p /tmp/empty_ramdisk
        cd /tmp/empty_ramdisk
        find . | cpio -H newc -o 2>/dev/null | gzip > "$ramdisk"
    fi
    
    # catdt mode (Image+DTB concatenation)
    log_info "Creating boot image (catdt mode)..."
    local kernel_dtb="$OUTPUT_DIR/zImage-dtb" 
    if command -v mkbootimg >/dev/null 2>&1; then
        mkbootimg --kernel "$kernel_dtb" 
            --ramdisk "$ramdisk" 
            --pagesize 2048 
            --cmdline "console=tty0 loglevel=7 ignore_loglevel" 
            -o "$OUTPUT_DIR/boot-catdt.img"
    else
        log_warn "mkbootimg not found, using abootimg instead"
        abootimg --create "$OUTPUT_DIR/boot-catdt.img" 
            -f "$OUTPUT_DIR/bootimg.cfg" 
            -k "$kernel_dtb" 
            -r "$ramdisk"
    fi
    
    # with-dt mode (separate DTB)
    log_info "Creating boot image (with-dt mode)..."
    if command -v mkbootimg >/dev/null 2>&1; then
        mkbootimg --kernel "$OUTPUT_DIR/Image" 
            --dt "$OUTPUT_DIR/dtb.img" 
            --ramdisk "$ramdisk" 
            --pagesize 2048 
            --cmdline "console=tty0 loglevel=7 ignore_loglevel" 
            -o "$OUTPUT_DIR/boot-with-dt.img"
    else
        log_warn "mkbootimg not found, using abootimg instead"
        abootimg --create "$OUTPUT_DIR/boot-with-dt.img" 
            -f "$OUTPUT_DIR/bootimg.cfg" 
            -k "$OUTPUT_DIR/Image" 
            -r "$ramdisk" 
            -s "$OUTPUT_DIR/dtb.img"
    fi
    
    # Create a symbolic link to the chosen packaging method
    if [[ "$PACKAGE_MODE" == "catdt" ]]; then
        cp "$OUTPUT_DIR/boot-catdt.img" "$OUTPUT_DIR/boot-new.img"
        log_info "Using catdt mode boot image as default"
    else
        cp "$OUTPUT_DIR/boot-with-dt.img" "$OUTPUT_DIR/boot-new.img"
        log_info "Using with-dt mode boot image as default"
    fi
    
    log_info "Boot images created successfully"
}

install_kernel_modules() {
    log_info "Installing kernel modules to output dir..."
    mkdir -p "$TEMP_BUILD_DIR/modules"
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" 
        INSTALL_MOD_PATH="$TEMP_BUILD_DIR/modules" modules_install > /dev/null 2>&1
        
    # Package modules into rootfs for later installation
    cd "$TEMP_BUILD_DIR/modules"
    tar -czf "$OUTPUT_DIR/modules.tar.gz" .
    log_info "Kernel modules packaged successfully"
}
