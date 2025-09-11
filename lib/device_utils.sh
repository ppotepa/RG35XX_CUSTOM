#!/bin/bash
# Device utilities for RG35XX-H
# Consolidated device detection and management functions

# Guard against multiple sourcing
[[ -n "${RG35XX_DEVICE_UTILS_LOADED:-}" ]] && return 0
export RG35XX_DEVICE_UTILS_LOADED=1

# Import logger if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/logger.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
else
    # Minimal logger functionality if not available
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# Detect RG35XX-H device based on partition schema
# Sets global variables:
# - EMMC_DEV: Main device (e.g. /dev/sdc)
# - BOOT_PART: Boot partition (e.g. /dev/sdc4)
# - ROOT_PART: Root partition (e.g. /dev/sdc5)
detect_rg35xx_device() {
    log_info "Auto-detecting RG35XX-H device based on partition schema..."
    
    # Check each potential device
    for dev in /dev/sd[a-z] /dev/mmcblk[0-9]; do
        [[ -b "$dev" ]] || continue
        
        local boot_part=""
        local root_part=""
        
        # Handle different naming conventions for sd* vs mmcblk*
        if [[ "$dev" =~ /dev/sd[a-z] ]]; then
            local boot_candidate="${dev}4"
            local root_candidate="${dev}5"
        else
            local boot_candidate="${dev}p4"
            local root_candidate="${dev}p5"
        fi
        
        # Check if partitions exist
        [[ -b "$boot_candidate" ]] || continue
        [[ -b "$root_candidate" ]] || continue
        
        # Get sizes to verify it's an RG35XX-H card
        local boot_size=$(lsblk -bno SIZE "$boot_candidate" 2>/dev/null || echo "0")
        local root_size=$(lsblk -bno SIZE "$root_candidate" 2>/dev/null || echo "0")
        
        # Verify sizes are reasonable for RG35XX-H
        if [[ -n "$boot_size" && -n "$root_size" ]]; then
            local boot_mb=$((boot_size / 1024 / 1024))
            local root_gb=$((root_size / 1024 / 1024 / 1024))
            
            # Boot should be ~64MB, root ~7GB for RG35XX-H
            if [[ $boot_mb -lt 100 && $root_gb -ge 6 && $root_gb -le 8 ]]; then
                log_info "Found RG35XX-H device: $dev (boot: ${boot_mb}MB, root: ${root_gb}GB)"
                EMMC_DEV="$dev"
                BOOT_PART="$boot_candidate"
                ROOT_PART="$root_candidate"
                return 0
            fi
        fi
    done
    
    # Fallback to /dev/sdc if detection fails
    if [[ -b "/dev/sdc4" && -b "/dev/sdc5" ]]; then
        log_warn "Auto-detection failed, using fallback: /dev/sdc"
        EMMC_DEV="/dev/sdc"
        BOOT_PART="/dev/sdc4"
        ROOT_PART="/dev/sdc5"
        return 0
    fi
    
    log_error "Could not detect RG35XX-H device!"
    return 1
}

# Validate detected device is accessible and has correct partition schema
validate_device() {
    local device="${1:-$EMMC_DEV}"
    local boot_part="${2:-$BOOT_PART}"
    local root_part="${3:-$ROOT_PART}"
    
    [[ -z "$device" ]] && { log_error "No device specified!"; return 1; }
    [[ -z "$boot_part" ]] && { log_error "No boot partition specified!"; return 1; }
    [[ -z "$root_part" ]] && { log_error "No root partition specified!"; return 1; }
    
    # Check device exists
    [[ -b "$device" ]] || { log_error "Device $device does not exist!"; return 1; }
    [[ -b "$boot_part" ]] || { log_error "Boot partition $boot_part does not exist!"; return 1; }
    [[ -b "$root_part" ]] || { log_error "Root partition $root_part does not exist!"; return 1; }
    
    # Check partition sizes
    local boot_size=$(lsblk -bno SIZE "$boot_part" 2>/dev/null || echo "0")
    local root_size=$(lsblk -bno SIZE "$root_part" 2>/dev/null || echo "0")
    
    # Verify sizes
    local boot_mb=$((boot_size / 1024 / 1024))
    local root_gb=$((root_size / 1024 / 1024 / 1024))
    
    [[ $boot_mb -lt 10 ]] && { log_error "Boot partition too small: ${boot_mb}MB"; return 1; }
    [[ $root_gb -lt 1 ]] && { log_error "Root partition too small: ${root_gb}GB"; return 1; }
    
    log_success "Device validation passed: $device"
    return 0
}

# Generate kernel command line for detected device
generate_kernel_cmdline() {
    local root_part="${1:-$ROOT_PART}"
    local template="${2:-$KCMD_TEMPLATE}"
    
    [[ -z "$root_part" ]] && { log_error "No root partition for cmdline!"; return 1; }
    [[ -z "$template" ]] && { 
        log_error "No command line template!"; 
        # Fallback template
        template="root=ROOT_PARTITION rw rootwait console=tty0 loglevel=7 ignore_loglevel fbcon=map:1 fbcon=nodefer video=640x480-32 vt.global_cursor_default=0"
    }
    
    # Replace placeholder with actual root partition
    local cmdline="${template/ROOT_PARTITION/$root_part}"
    
    echo "$cmdline"
    return 0
}

# Mount device for operations
mount_device() {
    local root_part="${1:-$ROOT_PART}"
    local mount_point="${2:-/mnt/rg35xx}"
    
    [[ -z "$root_part" ]] && { log_error "No root partition to mount!"; return 1; }
    
    # Create mount point if it doesn't exist
    mkdir -p "$mount_point"
    
    # Mount if not already mounted
    if ! findmnt "$mount_point" >/dev/null; then
        mount "$root_part" "$mount_point" || { 
            log_error "Failed to mount $root_part to $mount_point!"; 
            return 1; 
        }
        log_info "Mounted $root_part to $mount_point"
        return 0
    else
        log_info "Already mounted at $mount_point"
        return 0
    fi
}

# Unmount device
unmount_device() {
    local mount_point="${1:-/mnt/rg35xx}"
    
    if findmnt "$mount_point" >/dev/null; then
        umount "$mount_point" || {
            log_error "Failed to unmount $mount_point!";
            return 1;
        }
        log_info "Unmounted $mount_point"
    fi
    return 0
}
