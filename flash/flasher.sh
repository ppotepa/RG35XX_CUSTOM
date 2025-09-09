#!/bin/bash
# SD card flashing functionality

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/device.sh"

flash_device() {
    step "Flashing SD card"
    
    # Unmount any existing mounts
    umount "${TARGET_DISK}"* 2>/dev/null || true
    
    create_backups
    flash_kernel
    flash_rootfs
    
    log "Flashing completed successfully!"
}

create_backups() {
    if [[ "${SKIP_BACKUP:-0}" != "1" ]]; then
        log "Creating backups..."
        dd_with_progress "$BOOT_PART" "$SCRIPT_DIR/backup_boot.img" "Backing up boot partition"
        dd_with_progress "$ROOT_PART" "$SCRIPT_DIR/backup_rootfs.img" "Backing up rootfs partition"
    fi
}

flash_kernel() {
    dd_with_progress "$BUILD_DIR/out/zImage-dtb" "$BOOT_PART" "Writing kernel to boot partition"
}

flash_rootfs() {
    log "Formatting root partition..."
    mkfs.ext4 -F -q "$ROOT_PART"
    
    local mount_point="/mnt/rg35xx_root"
    mkdir -p "$mount_point"
    mount "$ROOT_PART" "$mount_point"
    
    copy_rootfs_files "$mount_point"
    
    sync
    umount "$mount_point"
    rmdir "$mount_point"
}

copy_rootfs_files() {
    local mount_point="$1"
    
    log "Copying root filesystem..."
    
    # Calculate total files for progress
    local total_files=$(find "$BUILD_DIR/rootfs" -type f | wc -l)
    local current_file=0
    
    # Copy files with progress
    find "$BUILD_DIR/rootfs" -type f | while read -r file; do
        local relative_path="${file#$BUILD_DIR/rootfs/}"
        local target_dir="$mount_point/$(dirname "$relative_path")"
        mkdir -p "$target_dir"
        cp "$file" "$target_dir/"
        
        current_file=$((current_file + 1))
        if [ $((current_file % 10)) -eq 0 ] || [ $current_file -eq $total_files ]; then
            show_progress $current_file $total_files "Copying rootfs files"
        fi
    done
    
    # Copy directories and special files
    rsync -a --exclude='*' "$BUILD_DIR/rootfs/" "$mount_point/"
}
