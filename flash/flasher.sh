#!/bin/bash
# SD card flashing functionality

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/device.sh"

flash_device() {
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
    
    # Validate pagesize
    if command -v abootimg >/dev/null 2>&1; then
        log_info "Verifying boot image pagesize..."
        local pagesize=$(abootimg -i "$boot_image" 2>/dev/null | grep -oP 'Page size: \K[0-9]+')
        if [[ "$pagesize" != "2048" ]]; then
            log_warn "Boot image has incorrect page size: $pagesize (should be 2048)"
            log_info "Attempting to recreate boot image with correct pagesize..."
            
            # Extract components
            local tmp_dir="/tmp/rg35xx_boot_fix"
            mkdir -p "$tmp_dir"
            abootimg -x "$boot_image" "$tmp_dir"
            
            # Recreate with correct pagesize
            abootimg --create "$boot_image.fixed" \
                -f "$tmp_dir/bootimg.cfg" \
                -k "$tmp_dir/zImage" \
                -r "$tmp_dir/initrd.img" \
                --pagesize 2048
                
            # Replace original
            mv "$boot_image.fixed" "$boot_image"
            rm -rf "$tmp_dir"
        fi
    fi
    
    # Flash the boot image
    dd_with_progress "$boot_image" "$BOOT_PART" "Writing boot image (pagesize 2048)"
    
    log_success "Kernel flashed successfully"
    
    # Verify after flash
    log_info "Verifying boot partition..."
    sync
    if command -v abootimg >/dev/null 2>&1; then
        abootimg -i "$BOOT_PART" || log_warn "Boot image verification failed"
    else
        file -s "$BOOT_PART" | grep -q "Android bootimg" || log_warn "Boot image might not be valid"
    fi
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
    
    log_info "Setting up device nodes..."
    mknod "$mount_point/dev/console" c 5 1 2>/dev/null || true
    mknod "$mount_point/dev/null" c 1 3 2>/dev/null || true
    mknod "$mount_point/dev/zero" c 1 5 2>/dev/null || true
    
    log_info "Setting correct permissions..."
    chmod +x "$mount_point/init" 2>/dev/null || true
    
    log_success "Root filesystem files copied"
}
