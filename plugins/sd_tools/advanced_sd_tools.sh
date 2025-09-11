#!/bin/bash
# Advanced SD card management and recovery tools

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/logger.sh"
source "$SCRIPT_DIR/config/constants.sh"

# Enhanced SD card diagnostics
enhanced_sd_diagnostics() {
    log_step "Enhanced SD card diagnostics"
    
    if [[ -z "$TARGET_DISK" ]]; then
        log_error "No target disk specified"
        return 1
    fi
    
    # Basic disk information
    log_info "=== Physical Disk Information ==="
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID "$TARGET_DISK" 2>/dev/null || {
        log_error "Cannot read disk information for $TARGET_DISK"
        return 1
    }
    
    # Disk health check
    log_info "=== Disk Health Check ==="
    if command -v smartctl >/dev/null 2>&1; then
        smartctl -H "$TARGET_DISK" 2>/dev/null | grep -E "(SMART|Health|Temperature)" || {
            log_info "SMART data not available (normal for SD cards)"
        }
    else
        log_info "smartmontools not available for health check"
    fi
    
    # Read/write speed test
    log_info "=== Speed Test ==="
    local test_file="${TARGET_DISK}1"
    if [[ -b "$test_file" ]]; then
        log_info "Testing read speed..."
        local read_speed=$(dd if="$test_file" of=/dev/null bs=1M count=100 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
        log_info "Read speed: ${read_speed:-unknown}"
    fi
    
    # Partition analysis
    log_info "=== Partition Analysis ==="
    fdisk -l "$TARGET_DISK" 2>/dev/null | grep -E "(Device|Units|Sector)" || {
        log_warn "Cannot read partition table"
    }
    
    # Check for bad sectors (basic)
    log_info "=== Basic Integrity Check ==="
    if badblocks -v -n "$TARGET_DISK" 2>/dev/null | head -10; then
        log_success "No bad blocks detected in sample"
    else
        log_info "Bad block check not available or failed"
    fi
    
    log_success "Diagnostics complete"
}

# Advanced backup creation
create_advanced_backup() {
    local backup_type="${1:-incremental}"
    local backup_dir="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)_${backup_type}"
    
    log_step "Creating $backup_type backup"
    mkdir -p "$backup_dir"
    
    case "$backup_type" in
        full)
            log_info "Creating full disk image backup..."
            dd if="$TARGET_DISK" of="$backup_dir/full_disk.img" bs=4M status=progress || {
                log_error "Full backup failed"
                return 1
            }
            ;;
        incremental)
            log_info "Creating incremental backup of critical partitions..."
            
            # Backup GPT
            sgdisk --backup="$backup_dir/gpt-backup.bin" "$TARGET_DISK"
            
            # Backup boot partition with compression
            dd if="${TARGET_DISK}4" bs=1M | gzip > "$backup_dir/boot-compressed.img.gz"
            
            # Backup configuration files from rootfs
            local temp_mount="/tmp/rootfs_backup_$$"
            mkdir -p "$temp_mount"
            if mount "${TARGET_DISK}5" "$temp_mount" 2>/dev/null; then
                log_info "Backing up system configuration..."
                tar -czf "$backup_dir/system_config.tar.gz" -C "$temp_mount" \
                    etc/fstab etc/passwd etc/group etc/hostname etc/hosts \
                    boot/config.txt 2>/dev/null || true
                umount "$temp_mount"
            fi
            rmdir "$temp_mount" 2>/dev/null
            ;;
        quick)
            log_info "Creating quick backup of essential data..."
            sgdisk --backup="$backup_dir/gpt-backup.bin" "$TARGET_DISK"
            dd if="${TARGET_DISK}4" of="$backup_dir/boot-quick.img" bs=1M count=64
            ;;
    esac
    
    # Create backup manifest
    cat > "$backup_dir/manifest.txt" << EOF
RG35XX_H Backup Manifest
========================
Created: $(date)
Type: $backup_type
Source Device: $TARGET_DISK
Host: $(hostname)

Contents:
EOF
    
    find "$backup_dir" -type f -exec basename {} \; | sort >> "$backup_dir/manifest.txt"
    
    # Create checksums
    (cd "$backup_dir" && sha256sum * > checksums.sha256 2>/dev/null)
    
    log_success "$backup_type backup created: $backup_dir"
}

# Recovery operations
perform_recovery() {
    local recovery_type="$1"
    local backup_dir="$2"
    
    log_step "Performing $recovery_type recovery"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    case "$recovery_type" in
        gpt)
            if [[ -f "$backup_dir/gpt-backup.bin" ]]; then
                log_info "Restoring GPT partition table..."
                sgdisk --load-backup="$backup_dir/gpt-backup.bin" "$TARGET_DISK" || {
                    log_error "GPT restoration failed"
                    return 1
                }
                log_success "GPT partition table restored"
            else
                log_error "GPT backup not found"
                return 1
            fi
            ;;
        boot)
            local boot_img=""
            if [[ -f "$backup_dir/boot-compressed.img.gz" ]]; then
                boot_img="$backup_dir/boot-compressed.img.gz"
                log_info "Restoring compressed boot partition..."
                gunzip -c "$boot_img" | dd of="${TARGET_DISK}4" bs=1M
            elif [[ -f "$backup_dir/boot-quick.img" ]]; then
                boot_img="$backup_dir/boot-quick.img"
                log_info "Restoring boot partition..."
                dd if="$boot_img" of="${TARGET_DISK}4" bs=1M
            else
                log_error "No boot backup found"
                return 1
            fi
            log_success "Boot partition restored"
            ;;
        full)
            if [[ -f "$backup_dir/full_disk.img" ]]; then
                log_warn "This will completely overwrite $TARGET_DISK!"
                read -p "Are you sure? Type 'YES' to confirm: " confirm
                if [[ "$confirm" == "YES" ]]; then
                    log_info "Restoring full disk image..."
                    dd if="$backup_dir/full_disk.img" of="$TARGET_DISK" bs=4M status=progress
                    log_success "Full disk restored"
                else
                    log_info "Recovery cancelled"
                    return 1
                fi
            else
                log_error "Full disk backup not found"
                return 1
            fi
            ;;
    esac
}

# SD card optimization
optimize_sd_card() {
    log_step "Optimizing SD card for RG35XX_H"
    
    # Align partitions for better performance
    log_info "Checking partition alignment..."
    local alignment_ok=true
    
    for part in "${TARGET_DISK}1" "${TARGET_DISK}4" "${TARGET_DISK}5"; do
        if [[ -b "$part" ]]; then
            local start_sector=$(fdisk -l "$TARGET_DISK" | grep "$part" | awk '{print $2}')
            if [[ $((start_sector % 2048)) -ne 0 ]]; then
                log_warn "Partition $part not aligned to 1MB boundary"
                alignment_ok=false
            fi
        fi
    done
    
    if [[ "$alignment_ok" == "true" ]]; then
        log_success "All partitions properly aligned"
    else
        log_warn "Consider repartitioning for better performance"
    fi
    
    # Optimize filesystem parameters
    log_info "Optimizing filesystem parameters..."
    
    # Optimize ext4 filesystem on root partition
    if mount | grep -q "${TARGET_DISK}5"; then
        log_warn "Root filesystem is mounted, cannot optimize"
    else
        log_info "Optimizing ext4 filesystem..."
        tune2fs -o journal_data_writeback "${TARGET_DISK}5" 2>/dev/null || true
        tune2fs -O ^has_journal "${TARGET_DISK}5" 2>/dev/null || true
        e2fsck -f "${TARGET_DISK}5" >/dev/null 2>&1 || true
    fi
    
    log_success "SD card optimization complete"
}

# Main function
main() {
    case "${1:-help}" in
        diagnose)
            enhanced_sd_diagnostics
            ;;
        backup)
            create_advanced_backup "${2:-incremental}"
            ;;
        recover)
            if [[ -z "$3" ]]; then
                log_error "Usage: $0 recover <type> <backup_dir>"
                log_error "Types: gpt, boot, full"
                exit 1
            fi
            perform_recovery "$2" "$3"
            ;;
        optimize)
            optimize_sd_card
            ;;
        help)
            cat << 'EOF'
RG35XX_H SD Card Management Tool

Usage: $0 <command> [options]

Commands:
  diagnose              Run enhanced SD card diagnostics
  backup [type]         Create backup (full|incremental|quick)
  recover <type> <dir>  Recover from backup (gpt|boot|full)
  optimize              Optimize SD card for performance
  help                  Show this help

Examples:
  $0 diagnose                              # Run diagnostics
  $0 backup full                           # Create full backup
  $0 backup incremental                    # Create incremental backup
  $0 recover gpt backups/20240101_120000   # Recover GPT table
  $0 optimize                              # Optimize SD card

Environment Variables:
  TARGET_DISK           SD card device (e.g., /dev/sdc)
EOF
            ;;
        *)
            log_error "Unknown command: $1"
            log_error "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"

