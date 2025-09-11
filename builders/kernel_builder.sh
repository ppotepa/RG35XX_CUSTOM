#!/bin/bash
# Kernel building functionality for RG35XX-H
# Enhanced with better error handling and progress tracking

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/logger.sh"
source "$SCRIPT_DIR/config/constants.sh"
source "$SCRIPT_DIR/lib/ramdisk.sh" 2>/dev/null || true
source "$SCRIPT_DIR/lib/bootimg.sh" 2>/dev/null || true
source "$SCRIPT_DIR/modules/kernel.sh" 2>/dev/null || {
    log_warn "Centralized kernel module not found, using legacy implementation"
}

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
    
    # Force or optionally set kernel command line
    local cmdline_value
    if [[ -n "${CUSTOM_CMDLINE:-}" ]]; then
        cmdline_value="$CUSTOM_CMDLINE"
    else
        cmdline_value="$DEFAULT_CMDLINE"
    fi
    log_info "Applying kernel cmdline: $cmdline_value"
    sed -i '/^CONFIG_CMDLINE=/d' .config || true
    echo "CONFIG_CMDLINE=\"$cmdline_value\"" >> .config
    echo "CONFIG_CMDLINE_BOOL=y" >> .config
    if [[ "${NO_FORCE_CMDLINE:-false}" == "false" ]]; then
        echo "CONFIG_CMDLINE_FORCE=y" >> .config
    else
        log_warn "CONFIG_CMDLINE_FORCE disabled by user"
    fi
    
    log "Resolving configuration dependencies..."
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
}

# Research-based LCD console configuration for RG35XX-H
apply_lcd_console_config() {
    log_info "Applying research-based LCD console configuration for RG35XX-H"
    
    # Create temporary config file with LCD console settings
    local lcd_config="$BUILD_DIR/lcd_console.config"
    cat > "$lcd_config" << 'EOF'
# Research-backed kernel configuration for RG35XX-H LCD console
# Based on Knulli project and successful community implementations

# Framebuffer Console Support
CONFIG_FB=y
CONFIG_FB_CFB_FILLRECT=y
CONFIG_FB_CFB_COPYAREA=y  
CONFIG_FB_CFB_IMAGEBLIT=y
CONFIG_FB_SYS_FILLRECT=y
CONFIG_FB_SYS_COPYAREA=y
CONFIG_FB_SYS_IMAGEBLIT=y
CONFIG_FB_SYS_FOPS=y
CONFIG_FB_DEFERRED_IO=y
CONFIG_FB_MODE_HELPERS=y
CONFIG_FB_TILEBLITTING=y

# VT Console Support  
CONFIG_VT=y
CONFIG_CONSOLE_TRANSLATIONS=y
CONFIG_VT_CONSOLE=y
CONFIG_VT_HW_CONSOLE_BINDING=y

# Framebuffer Console - CRITICAL for LCD visibility
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
# CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is not set
CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y

# DRM Support for Allwinner Display Engine
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_KMS_FB_HELPER=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_FBDEV_OVERALLOC=100
CONFIG_DRM_SUN4I=y
CONFIG_DRM_SUN6I_DSI=y
CONFIG_DRM_SUN8I_DW_HDMI=y
CONFIG_DRM_SUN8I_MIXER=y

# Simple framebuffer for early console
CONFIG_FB_SIMPLE=y

# Logo display during boot
CONFIG_LOGO=y
CONFIG_LOGO_LINUX_MONO=y
CONFIG_LOGO_LINUX_VGA16=y
CONFIG_LOGO_LINUX_CLUT224=y

# Font support for console readability
CONFIG_FONTS=y
CONFIG_FONT_8x8=y
CONFIG_FONT_8x16=y
CONFIG_FONT_6x11=y
CONFIG_FONT_7x14=y
CONFIG_FONT_PEARL_8x8=y
CONFIG_FONT_ACORN_8x8=y
CONFIG_FONT_MINI_4x6=y
CONFIG_FONT_SUN8x16=y
CONFIG_FONT_SUN12x22=y
CONFIG_FONT_10x18=y
CONFIG_FONT_TER16x32=y

# Hardware specific - Allwinner H616/H700
CONFIG_ARCH_SUNXI=y
CONFIG_ARM64=y
CONFIG_PINCTRL_SUN50I_H616=y
CONFIG_CLK_SUNXI=y
CONFIG_RESET_SUNXI=y

# Essential debugging and logging
CONFIG_MAGIC_SYSRQ=y
CONFIG_PRINTK=y
CONFIG_PRINTK_TIME=y
CONFIG_DYNAMIC_DEBUG=y
CONFIG_DEBUG_KERNEL=y

# Input devices for console interaction
CONFIG_INPUT_KEYBOARD=y
CONFIG_KEYBOARD_GPIO=y
CONFIG_KEYBOARD_GPIO_POLLED=y

# TTY and console essentials
CONFIG_TTY=y
CONFIG_UNIX98_PTYS=y
CONFIG_DEVPTS_MULTIPLE_INSTANCES=y
EOF

    # Apply the LCD console configuration using merge_config.sh
    log_info "Merging LCD console configuration with kernel config..."
    if [[ -f scripts/kconfig/merge_config.sh ]]; then
        ./scripts/kconfig/merge_config.sh -m .config "$lcd_config" || log_warn "LCD console config merge returned non-zero"
        log_success "LCD console configuration applied successfully"
    else
        log_warn "merge_config.sh not found, applying configuration manually..."
        # Fallback: apply settings manually
        apply_config_fallback "$lcd_config"
    fi
    
    # Clean up temporary config file
    rm -f "$lcd_config"
}

apply_custom_config() {
    # Apply research-based LCD console configuration first
    log_info "Applying research-based LCD console configuration..."
    apply_lcd_console_config
    
    # Check for config_patch in multiple locations with priority for current working directory
    local patch_file=""
    local patch_dir=""
    
    # First check current working directory
    if [[ -f "$PWD/config_patch" ]]; then
        log_info "Using config_patch from current directory: $PWD"
        patch_file="$PWD/config_patch"
    elif [[ -d "$PWD/config_patch" ]]; then
        log_info "Using config_patch directory from current directory: $PWD"
        patch_dir="$PWD/config_patch"
    # Then check script directory
    elif [[ -f "$SCRIPT_DIR/config_patch" ]]; then
        log_info "Using config_patch from script directory"
        patch_file="$SCRIPT_DIR/config_patch"
    elif [[ -d "$SCRIPT_DIR/config_patch" ]]; then
        log_info "Using config_patch directory from script directory"
        patch_dir="$SCRIPT_DIR/config_patch"
    else
        log_warn "No config_patch found, using default configuration"
        return
    fi
    
    log_info "Applying custom configuration..."
    
    # Use proper merge_config.sh for best compatibility
    if [[ -n "$patch_dir" ]]; then
        # Apply all configs from directory
        log_info "Merging configs from directory: $patch_dir"
        ./scripts/kconfig/merge_config.sh -m .config "$patch_dir"/*.config || log_warn "merge_config.sh returned non-zero"
    elif [[ -n "$patch_file" ]]; then
        # Apply single config file
        log_info "Merging config from file: $patch_file"
        ./scripts/kconfig/merge_config.sh -m .config "$patch_file" || log_warn "merge_config.sh returned non-zero"
    else
        log_warn "No config patch applied - using default config"
    fi
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
    # Monotonic, weighted progress: estimate work by SLOC in major module trees
    local PROG_BASE=60 PROG_END=85 PROG_RANGE=$((PROG_END-PROG_BASE))
    declare -A UNIT_WEIGHT
    declare -A SEEN_UNIT
    local TOTAL_WEIGHT=0 ACC_WEIGHT=0 CUR_PROG=$PROG_BASE
    # Pre-compute weights by counting lines in .c files (fallback weight=1)
    while IFS= read -r -d '' src; do
        local lines
        lines=$(wc -l < "$src" 2>/dev/null || echo 0)
        [[ "$lines" =~ ^[0-9]+$ ]] || lines=0
        (( lines == 0 )) && lines=1
        UNIT_WEIGHT["$src"]=$lines
        TOTAL_WEIGHT=$((TOTAL_WEIGHT+lines))
    done < <(find drivers fs sound net crypto -type f -name '*.c' -print0 2>/dev/null)
    log_info "Module weighting total SLOC: $TOTAL_WEIGHT"

    # Build and update progress based on compiled objects observed in output
    make -j"$BUILD_JOBS" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" modules 2>&1 | while IFS= read -r line; do
        if [[ "$line" =~ (CC|CXX|LD|AR)[[:space:]]+([^[:space:]]+\.o) ]]; then
            obj="${BASH_REMATCH[2]}"
            # Normalize obj path (strip leading ./)
            [[ "$obj" == ./* ]] && obj="${obj:2}"
            src="${obj%.o}.c"
            weight="${UNIT_WEIGHT[$src]}"
            [[ -z "$weight" ]] && weight=1
            if [[ -z "${SEEN_UNIT[$src]}" ]]; then
                SEEN_UNIT["$src"]=1
                ACC_WEIGHT=$((ACC_WEIGHT+weight))
                if (( TOTAL_WEIGHT > 0 )); then
                    local target=$(( PROG_BASE + (ACC_WEIGHT * PROG_RANGE) / TOTAL_WEIGHT ))
                    if (( target > CUR_PROG )); then
                        CUR_PROG=$target
                        local pct=$(( (ACC_WEIGHT * 100) / (TOTAL_WEIGHT>0?TOTAL_WEIGHT:1) ))
                        update_progress "$CUR_PROG" "Compiling modules... ${pct}% ($(basename "${obj}"))"
                    fi
                fi
            fi
        fi
        # Light feedback on module linking without affecting progress
        if [[ "$line" =~ ^LD\ \[M\]\ (.+) ]]; then
            : # could log or keep silent to avoid jitter
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

    # Attempt unified ramdisk extraction from any existing backup (heuristic)
    local ramdisk="/tmp/rg35haxx_ramdisk.cpio.gz"
    if [[ ! -f "$ramdisk" ]]; then
        if [[ -f "$SCRIPT_DIR/backups/boot-p4-backup.img" ]]; then
            extract_ramdisk "$SCRIPT_DIR/backups/boot-p4-backup.img" "$ramdisk" || true
        fi
    fi
        # Create minimal if still missing
    if [[ ! -f "$ramdisk" ]]; then
                log_warn "No stock ramdisk available; generating minimal switch_root initramfs"
                local tmpdir=$(mktemp -d)
                cat > "$tmpdir/init" << 'IRAM'
#!/bin/sh
exec >/dev/tty0 2>&1
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo "[initramfs] starting, cmdline: $(cat /proc/cmdline)"
# find root
ROOTDEV=""
for c in /dev/disk/by-partlabel/rootfs /dev/mmcblk0p2 /dev/mmcblk1p2 /dev/mmcblk2p2; do
    [ -e "$c" ] && { ROOTDEV="$c"; break; }
done
if [ -n "$ROOTDEV" ]; then
    mkdir -p /newroot
    mount "$ROOTDEV" /newroot || mount -t ext4 "$ROOTDEV" /newroot || echo "[initramfs] mount failed"
    if [ -d /newroot ]; then
        mount --move /dev /newroot/dev 2>/dev/null || true
        mount --move /proc /newroot/proc 2>/dev/null || true
        mount --move /sys /newroot/sys 2>/dev/null || true
        exec switch_root /newroot /sbin/init || exec chroot /newroot /sbin/init || exec chroot /newroot /init
    fi
fi
echo "[initramfs] dropping to shell"
exec sh
IRAM
                chmod +x "$tmpdir/init"
                (cd "$tmpdir" && mkdir -p dev proc sys etc && find . | cpio -H newc -o | gzip > "$ramdisk")
                rm -rf "$tmpdir"
    fi

    # catdt mode (Image+DTB concatenation)
    log_info "Creating boot image (catdt mode)..."
    local kernel_dtb="$OUTPUT_DIR/zImage-dtb"
    if command -v mkbootimg >/dev/null 2>&1; then
        local mkargs
        if [[ -f "$SCRIPT_DIR/backups/boot-p4-backup.img" ]]; then
            mkargs=$(bootimg_generate_mkbootimg_args "$SCRIPT_DIR/backups/boot-p4-backup.img") || mkargs="--pagesize $BOOT_IMAGE_PAGE_SIZE"
        else
            mkargs="--pagesize $BOOT_IMAGE_PAGE_SIZE"
        fi
        # Ensure correct page size is used
        mkargs=$(echo "$mkargs" | sed "s/--pagesize [0-9]*/--pagesize $BOOT_IMAGE_PAGE_SIZE/")
        mkbootimg --kernel "$kernel_dtb" --ramdisk "$ramdisk" $mkargs \
            --cmdline "${CUSTOM_CMDLINE:-$DEFAULT_CMDLINE}" -o "$OUTPUT_DIR/boot-catdt.img"
        
        # Verify and fix page size if needed
        if ! verify_boot_image_page_size "$OUTPUT_DIR/boot-catdt.img"; then
            log_warn "Fixing boot image page size for catdt mode..."
            fix_boot_image_page_size "$OUTPUT_DIR/boot-catdt.img" "$OUTPUT_DIR/boot-catdt-fixed.img"
            mv "$OUTPUT_DIR/boot-catdt-fixed.img" "$OUTPUT_DIR/boot-catdt.img"
        fi
    else
        # Fallback: create using bootimg helper
        log_warn "mkbootimg not found, using alternative method for catdt"
        create_boot_image_from_components "$kernel_dtb" "$ramdisk" "$OUTPUT_DIR/boot-catdt.img"
    fi

    # with-dt mode (separate DTB)
    log_info "Creating boot image (with-dt mode)..."
    if command -v mkbootimg >/dev/null 2>&1; then
        local mkargs2
        if [[ -f "$SCRIPT_DIR/backups/boot-p4-backup.img" ]]; then
            mkargs2=$(bootimg_generate_mkbootimg_args "$SCRIPT_DIR/backups/boot-p4-backup.img") || mkargs2="--pagesize $BOOT_IMAGE_PAGE_SIZE"
        else
            mkargs2="--pagesize $BOOT_IMAGE_PAGE_SIZE"
        fi
        # Ensure correct page size is used
        mkargs2=$(echo "$mkargs2" | sed "s/--pagesize [0-9]*/--pagesize $BOOT_IMAGE_PAGE_SIZE/")
        mkbootimg --kernel "$OUTPUT_DIR/Image" --dt "$OUTPUT_DIR/dtb.img" \
            --ramdisk "$ramdisk" $mkargs2 --cmdline "${CUSTOM_CMDLINE:-$DEFAULT_CMDLINE}" \
            -o "$OUTPUT_DIR/boot-with-dt.img"
        
        # Verify and fix page size if needed
        if ! verify_boot_image_page_size "$OUTPUT_DIR/boot-with-dt.img"; then
            log_warn "Fixing boot image page size for with-dt mode..."
            fix_boot_image_page_size "$OUTPUT_DIR/boot-with-dt.img" "$OUTPUT_DIR/boot-with-dt-fixed.img"
            mv "$OUTPUT_DIR/boot-with-dt-fixed.img" "$OUTPUT_DIR/boot-with-dt.img"
        fi
    else
        # Fallback: create using bootimg helper
        log_warn "mkbootimg not found, using alternative method for with-dt"
        create_boot_image_from_components "$OUTPUT_DIR/Image" "$ramdisk" "$OUTPUT_DIR/boot-with-dt.img" "$OUTPUT_DIR/dtb.img"
    fi

    # Select preferred packaging mode and create boot-new.img
    if [[ "$PACKAGE_MODE" == "catdt" && -f "$OUTPUT_DIR/boot-catdt.img" ]]; then
        cp "$OUTPUT_DIR/boot-catdt.img" "$OUTPUT_DIR/boot-new.img"
        log_info "Using catdt mode boot image as default"
    elif [[ -f "$OUTPUT_DIR/boot-with-dt.img" ]]; then
        cp "$OUTPUT_DIR/boot-with-dt.img" "$OUTPUT_DIR/boot-new.img"
        log_info "Using with-dt mode boot image as default"
    else
        log_error "No boot image was created successfully!"
        # Emergency fallback: create basic boot image
        log_info "Creating emergency fallback boot image..."
        if [[ -f "$OUTPUT_DIR/zImage-dtb" ]]; then
            create_boot_image_from_components "$OUTPUT_DIR/zImage-dtb" "$ramdisk" "$OUTPUT_DIR/boot-new.img"
        elif [[ -f "$OUTPUT_DIR/Image" ]]; then
            create_boot_image_from_components "$OUTPUT_DIR/Image" "$ramdisk" "$OUTPUT_DIR/boot-new.img"
        else
            log_error "No kernel image available for boot image creation!"
            return 1
        fi
    fi

    # Final verification of boot-new.img
    if [[ -f "$OUTPUT_DIR/boot-new.img" ]]; then
        log_info "Verifying final boot image..."
        get_boot_image_info "$OUTPUT_DIR/boot-new.img"
        if verify_boot_image_page_size "$OUTPUT_DIR/boot-new.img"; then
            log_success "Boot image created successfully with correct page size: $OUTPUT_DIR/boot-new.img"
        else
            log_error "Final boot image has incorrect page size!"
            return 1
        fi
    else
        log_error "boot-new.img was not created!"
        return 1
    fi

    log_info "Boot images creation step finished"
}

install_kernel_modules() {
    log_info "Installing kernel modules to output dir..."
    mkdir -p "$TEMP_BUILD_DIR/modules"
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" INSTALL_MOD_PATH="$TEMP_BUILD_DIR/modules" modules_install > /dev/null 2>&1
        
    # Package modules into rootfs for later installation
    cd "$TEMP_BUILD_DIR/modules"
    tar -czf "$OUTPUT_DIR/modules.tar.gz" .
    log_info "Kernel modules packaged successfully"
}
