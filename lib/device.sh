#!/bin/bash
# Device detection and SD card management

 # Guard against multiple sourcing
 [[ -n "${RG35HAXX_DEVICE_LOADED:-}" ]] && return 0
 export RG35HAXX_DEVICE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

detect_device() {
    log_step "Detecting device type"
    log_info "Target device: RG35HAXX (Anbernic RG35XX-H)"
    log_info "Architecture: ARM64 (Allwinner H700)"
    log_info "Device tree: ${DEVICE_DTB}"
}

configure_device_specific_settings() {
    log_step "Configuring device-specific settings"
    
    # Set device-specific environment variables
    export DEVICE_TYPE="RG35HAXX"
    export DISPLAY_ORIENTATION="landscape"
    export AUDIO_DRIVER="sun4i-i2s"
    export INPUT_DEVICES="gpio-keys,sun4i-ts"
    
    log_info "Device configuration completed for $DEVICE_TYPE"
}

readonly RG35HAXX_DEVICE_LOADED=1

detect_sd_card() {
    log_step "Detecting RG35XX_H SD card"
    
    local target_disk=""
    while IFS= read -r disk; do
        local boot_part=$(lsblk -nr -o NAME,PARTLABEL "$disk" | awk '$2=="boot"{print "/dev/"$1}' | head -1)
        local root_part=$(lsblk -nr -o NAME,PARTLABEL "$disk" | awk '$2=="rootfs"{print "/dev/"$1}' | head -1)
        
        if [[ -n "$boot_part" && -n "$root_part" ]]; then
            target_disk="$disk"
            break
        fi
    done < <(lsblk -dn -o NAME,TYPE,RM | awk '$2=="disk" && $3=="1" {print "/dev/"$1}')
    
    if [[ -z "$target_disk" ]]; then
        log_warn "No RG35XX_H SD card found. Insert SD card to enable flashing."
        return 1
    fi
    
    export TARGET_DISK="$target_disk"
    export BOOT_PART=$(lsblk -nr -o NAME,PARTLABEL "$TARGET_DISK" | awk '$2=="boot"{print "/dev/"$1}' | head -1)
    export ROOT_PART=$(lsblk -nr -o NAME,PARTLABEL "$TARGET_DISK" | awk '$2=="rootfs"{print "/dev/"$1}' | head -1)
    
    log_info "Target disk: $TARGET_DISK"
    log_info "Boot partition: $BOOT_PART"
    log_info "Root partition: $ROOT_PART"
    
    return 0
}

dd_with_progress() {
    local input="$1"
    local output="$2"
    local description="$3"
    
    local size=$(stat -c%s "$input" 2>/dev/null || echo "0")
    local size_mb=$((size / 1024 / 1024))
    local size_human=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size_mb}MB")
    
    if [ $size_mb -eq 0 ]; then
        log_info "$description (unknown size)..."
        dd if="$input" of="$output" bs=1M conv=fsync status=progress 2>/dev/null
        return
    fi
    
    log_info "$description ($size_human)..."
    
    if command -v pv >/dev/null 2>&1; then
        pv -p -t -e -r -b "$input" | dd of="$output" bs=1M conv=fsync 2>/dev/null
    else
        dd if="$input" of="$output" bs=1M conv=fsync status=progress 2>/dev/null
    fi
    
    sync
    log_success "$description completed ($size_human)"
}
