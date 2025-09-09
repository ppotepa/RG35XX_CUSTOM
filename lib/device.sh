#!/bin/bash
# Device detection and SD card management

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

detect_sd_card() {
    step "Detecting RG35XX_H SD card"
    
    local target_disk=""
    while IFS= read -r disk; do
        local boot_part=$(lsblk -nr -o NAME,PARTLABEL "$disk" | awk '$2=="boot"{print "/dev/"$1}' | head -1)
        local root_part=$(lsblk -nr -o NAME,PARTLABEL "$disk" | awk '$2=="rootfs"{print "/dev/"$1}' | head -1)
        
        if [[ -n "$boot_part" && -n "$root_part" ]]; then
            target_disk="$disk"
            break
        fi
    done < <(lsblk -dn -o NAME,TYPE,RM | awk '$2=="disk" && $3=="1" {print "/dev/"$1}')
    
    [[ -n "$target_disk" ]] || error "No RG35XX_H SD card found. Insert SD card and try again."
    
    readonly TARGET_DISK="$target_disk"
    readonly BOOT_PART=$(lsblk -nr -o NAME,PARTLABEL "$TARGET_DISK" | awk '$2=="boot"{print "/dev/"$1}' | head -1)
    readonly ROOT_PART=$(lsblk -nr -o NAME,PARTLABEL "$TARGET_DISK" | awk '$2=="rootfs"{print "/dev/"$1}' | head -1)
    
    log "Target disk: $TARGET_DISK"
    log "Boot partition: $BOOT_PART"
    log "Root partition: $ROOT_PART"
    
    confirm_flash_operation
}

confirm_flash_operation() {
    if [[ "${INTERACTIVE:-0}" == "1" ]]; then
        echo -e "\n${RED}WARNING: This will OVERWRITE the SD card!${NC}"
        read -p "Type 'YES' to continue: " confirm
        [[ "$confirm" == "YES" ]] || error "Aborted by user"
    else
        warn "Auto-flashing mode: SD card will be overwritten in 3 seconds..."
        sleep 3
    fi
}

dd_with_progress() {
    local input="$1"
    local output="$2"
    local description="$3"
    
    local size=$(stat -c%s "$input" 2>/dev/null || echo "0")
    local size_mb=$((size / 1024 / 1024))
    
    if [ $size_mb -eq 0 ]; then
        log "$description (unknown size)..."
        dd if="$input" of="$output" bs=1M conv=fsync status=progress 2>/dev/null
        return
    fi
    
    log "$description (${size_mb}MB)..."
    
    if command -v pv >/dev/null 2>&1; then
        pv -p -t -e -r -b "$input" | dd of="$output" bs=1M conv=fsync 2>/dev/null
    else
        dd if="$input" of="$output" bs=1M conv=fsync status=progress 2>/dev/null
    fi
    
    sync
    log "$description completed"
}
