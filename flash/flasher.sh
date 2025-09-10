#!/bin/bash
# SD card flashing functionality
# Ensure bash doesn't exit on unbound variables (some builds use set -u)
set +u

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/device.sh"

flash_device() {
    # Set default values for variables that might be undefined
    FULL_VERIFY=${FULL_VERIFY:-0}
    PAGE_SIZE=${PAGE_SIZE:-2048}
    PAGE_SIZE_OVERRIDE=${PAGE_SIZE_OVERRIDE:-}
    
    log_step "Flashing SD card"
    start_progress "flash" 100
    
    # Confirm the flash operation
    confirm_flash_operation
    
    update_progress 10 "Unmounting existing partitions..."
    # Unmount any existing mounts
    umount "${TARGET_DISK}"* 2>/dev/null || true
    
    update_progress 20 "Creating backups..."
    create_backups
    
    update_progress 50 "Flashing kernel..."
    flash_kernel
    
    update_progress 80 "Flashing rootfs..."
    flash_rootfs
    
    update_progress 100 "Flash complete"
    end_progress "SD card flashed successfully"
    log_success "Flashing completed successfully!"
}

confirm_flash_operation() {
    echo -e "\n${RED}WARNING: This will OVERWRITE the SD card ${TARGET_DISK}!${NC}"
    echo "Boot partition: $BOOT_PART"
    echo "Root partition: $ROOT_PART"
    read -p "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || { log_error "Flashing aborted by user"; return 1; }
}

create_backups() {
    if [[ "${SKIP_BACKUP:-false}" == "true" ]]; then
        log_warn "Skipping backups (--skip-backup specified)"
        return 0
    fi
    
    mkdir -p "$SCRIPT_DIR/backups"
    local backup_dir="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log_info "Creating backups in $backup_dir..."
    
    # Backup GPT
    log_info "Backing up GPT partition table..."
    sgdisk --backup="$backup_dir/gpt-backup.bin" "$TARGET_DISK" || log_warn "GPT backup failed"
    
    # Backup the boot partition (p4)
    dd_with_progress "$BOOT_PART" "$backup_dir/boot-p4-backup.img" "Backing up boot partition"
    
    # Backup just the modules directory from rootfs
    log_info "Creating modules backup..."
    local tmp_mount="/tmp/rg35xx_rootfs_backup"
    mkdir -p "$tmp_mount"
    mount "$ROOT_PART" "$tmp_mount" || { log_warn "Could not mount rootfs for selective backup"; umount "$tmp_mount" 2>/dev/null; }
    
    if [[ -d "$tmp_mount/lib/modules" ]]; then
        log_info "Backing up kernel modules..."
        tar -czf "$backup_dir/modules-backup.tar.gz" -C "$tmp_mount" lib/modules
    fi
    
    umount "$tmp_mount" 2>/dev/null
    rmdir "$tmp_mount" 2>/dev/null
    
    # Create checksums for verification
    ( cd "$backup_dir" && sha256sum * > checksums.sha256 )
    
    log_success "Backups created successfully in $backup_dir"
}

flash_kernel() {
    log_info "Flashing kernel to boot partition..."
    update_progress 55 "Writing kernel to boot partition..."
    
    # Select the appropriate boot image based on packaging mode
    local boot_image=""
    
    if [[ "$PACKAGE_MODE" == "catdt" ]]; then
        boot_image="$OUTPUT_DIR/boot-catdt.img"
        log_info "Using catdt mode boot image"
    else
        boot_image="$OUTPUT_DIR/boot-with-dt.img"
        log_info "Using with-dt mode boot image" 
    fi
    
    # If the specific boot image doesn't exist, fall back to boot-new.img
    if [[ ! -f "$boot_image" ]]; then
        boot_image="$OUTPUT_DIR/boot-new.img"
        log_info "Using default boot image"
    fi
    
    # If boot-new.img also doesn't exist, try to create it
    if [[ ! -f "$boot_image" ]]; then
        log_warn "Boot image not found: $boot_image"
        log_info "Attempting to create boot image..."
        
        # Try to run the boot image fix script
        if [[ -f "$SCRIPT_DIR/fix_boot_image.sh" ]]; then
            log_info "Running boot image creation script..."
            "$SCRIPT_DIR/fix_boot_image.sh" || {
                log_error "Failed to create boot image"
                return 1
            }
        else
            log_error "Boot image fix script not found and no boot image available"
            return 1
        fi
        
        # Check if boot image was created
        if [[ ! -f "$boot_image" ]]; then
            log_error "Boot image still not available after creation attempt"
            return 1
        fi
    fi
    
    # Validate pagesize
    if command -v abootimg >/dev/null 2>&1; then
        log_info "Verifying boot image pagesize..."
        local pagesize=$(abootimg -i "$boot_image" 2>/dev/null | grep -E "Page size|page size" | awk '{print $NF}' | tr -d ':')
        if [[ -z "$pagesize" ]]; then
            log_warn "Could not detect boot image page size - attempting extraction verification"
            pagesize="unknown"
        fi
        log_info "Detected boot image page size: ${pagesize}"
        if [[ "$pagesize" != "2048" ]] && [[ "$pagesize" != "unknown" ]]; then
            log_warn "Boot image has incorrect page size: $pagesize (should be 2048)"
            log_info "Attempting to recreate boot image with correct pagesize..."
            
            # Extract components to temporary directory
            local tmp_dir="/tmp/rg35xx_boot_fix"
            mkdir -p "$tmp_dir"
            
            if abootimg -x "$boot_image" "$tmp_dir/bootimg.cfg" "$tmp_dir/zImage" "$tmp_dir/initrd.img" 2>/dev/null; then
                # Update config file to use correct page size
                sed -i "s/pagesize .*/pagesize = 0x800/" "$tmp_dir/bootimg.cfg"
                
                # Recreate with correct pagesize
                abootimg --create "$boot_image.fixed" \
                    -f "$tmp_dir/bootimg.cfg" \
                    -k "$tmp_dir/zImage" \
                    -r "$tmp_dir/initrd.img" || {
                    log_error "Failed to recreate boot image"
                    rm -rf "$tmp_dir"
                    return 1
                }
                
                # Replace original
                mv "$boot_image.fixed" "$boot_image"
                log_success "Boot image recreated with correct page size"
            else
                log_error "Failed to extract boot image components"
                rm -rf "$tmp_dir"
                return 1
            fi
            
            # Clean up temporary directory
            rm -rf "$tmp_dir"
        else
            log_success "Boot image has correct page size: $pagesize"
        fi
    fi
    
    # Pre-flash verification setup
    local src_hash pre_full pre_partial
    if command -v sha256sum >/dev/null 2>&1; then
        src_hash=$(sha256sum "$boot_image" | awk '{print $1}')
        log_info "Source boot image SHA256: $src_hash"
        
        # Pre-verification for comparison
        if [[ ${FULL_VERIFY:-0} -eq 1 ]]; then
            pre_full="$src_hash"
        else
            # Partial verification - first 1MB hash
            dd if="$boot_image" bs=1M count=1 2>/dev/null | sha256sum | awk '{print $1}' > /tmp/pre_hash
            pre_partial=$(cat /tmp/pre_hash)
        fi
    fi

    # Flash the boot image
    dd_with_progress "$boot_image" "$BOOT_PART" "Writing boot image (pagesize ${PAGE_SIZE_OVERRIDE:-$PAGE_SIZE})"

    log_success "Kernel flashed successfully"

    # Verify after flash
    log_info "Verifying boot partition..."
    sync
    if command -v abootimg >/dev/null 2>&1; then
        abootimg -i "$BOOT_PART" || log_warn "Boot image header verification failed"
    else
        file -s "$BOOT_PART" | grep -q "Android bootimg" || log_warn "Boot image magic not detected"
    fi
    if [[ -n "$src_hash" ]]; then
        local dst_tmp="/tmp/rg35haxx_postflash_boot.img"
        dd if="$BOOT_PART" of="$dst_tmp" bs=4M count=16 status=none 2>/dev/null || true
        local dst_hash=$(sha256sum "$dst_tmp" | awk '{print $1}')
        rm -f "$dst_tmp"
        if [[ "$src_hash" == "$dst_hash" ]]; then
            log_success "Boot partition first-chunk hash matches source"
        else
            log_warn "Boot partition hash mismatch (first chunk). Full read skipped to save time."
        fi
    fi
    if [[ ${FULL_VERIFY:-0} -eq 1 && -n $(command -v sha256sum) ]]; then
        log_info "Full image verification enabled (may be slow)."
        bootimg_full_hash "$BOOT_PART" > /tmp/post_full 2>/dev/null || dd if="$BOOT_PART" bs=4M 2>/dev/null | sha256sum | awk '{print $1}' > /tmp/post_full
        local post_full=$(cat /tmp/post_full)
        if [[ "${pre_full:-}" == "$post_full" && -n "${pre_full:-}" ]]; then
            log_success "Full image verification PASSED (hash $post_full)"
        else
            log_warn "Full image verification mismatch. Expected: ${pre_full:-none} Got: $post_full"
        fi
    else
        log_info "Kernel image written. Performing partial verification (first 1MB hash)."
        dd if="$BOOT_PART" bs=1M count=1 2>/dev/null | sha256sum | awk '{print $1}' > /tmp/post_hash
        local post_partial=$(cat /tmp/post_hash)
        if [[ "${pre_partial:-}" == "$post_partial" ]]; then
            log_success "Partial verification PASSED (first 1MB hash matches)."
        else
            log_warn "Partial verification mismatch. (expected ${pre_partial:-none} got $post_partial)"
        fi
    fi
    
    # Clean up any temporary files
    log_info "Cleaning up temporary directory..."
    rm -f /tmp/post_full /tmp/post_hash /tmp/rg35haxx_postflash_boot.img 2>/dev/null || true
}

flash_rootfs() {
    log_info "Formatting root partition..."
    update_progress 75 "Formatting root partition..."
    mkfs.ext4 -F -q "$ROOT_PART"
    
    local mount_point="/mnt/rg35xx_root"
    mkdir -p "$mount_point"
    mount "$ROOT_PART" "$mount_point"
    
    update_progress 85 "Copying rootfs files..."
    copy_rootfs_files "$mount_point"
    
    sync
    umount "$mount_point"
    rmdir "$mount_point"
    log_success "Root filesystem flashed successfully"
}

copy_rootfs_files() {
    local mount_point="$1"
    
    log_info "Copying root filesystem..."
    
    # Use tar for efficient copying
    cd "$BUILD_DIR/rootfs"
    tar -cf - . | (cd "$mount_point" && tar -xf -)
    
    # Install kernel modules if available
    if [[ -f "$OUTPUT_DIR/modules.tar.gz" ]]; then
        log_info "Installing kernel modules into rootfs..."
        tar -xzf "$OUTPUT_DIR/modules.tar.gz" -C "$mount_point" || log_warn "Failed to extract modules archive"
    fi
    
    log_info "Setting up device nodes..."
    mknod "$mount_point/dev/console" c 5 1 2>/dev/null || true
    mknod "$mount_point/dev/null" c 1 3 2>/dev/null || true
    mknod "$mount_point/dev/zero" c 1 5 2>/dev/null || true
    
    log_info "Setting correct permissions..."
    chmod +x "$mount_point/init" 2>/dev/null || true
    
    log_success "Root filesystem files copied"
}
