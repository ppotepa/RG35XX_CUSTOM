#!/bin/bash
# RG35XX H SD Card Backup Tool
# This script creates comprehensive backups of an SD card

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")/../..")" && pwd)"

# Source required modules
source "$SCRIPT_DIR/lib/logger.sh" || { echo "ERROR: Failed to load logger"; exit 1; }
source "$SCRIPT_DIR/lib/device_utils.sh" || { echo "ERROR: Failed to load device management"; exit 1; }

# Default backup directory
BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d_%H%M%S)"

usage() {
  echo "RG35XX H SD Card Backup Tool"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --device=DEVICE      SD card device (default: auto-detect)"
  echo "  --dir=PATH           Backup directory (default: ./backups/TIMESTAMP)"
  echo "  --help               Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                         # Auto-detect SD card and create backup"
  echo "  $0 --device=/dev/sdc       # Backup specific device"
  echo "  $0 --dir=/mnt/backup       # Use custom backup directory"
  exit 1
}

# Parse arguments
DEVICE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --device=*)
      DEVICE="${1#*=}"
      shift
      ;;
    --dir=*)
      BACKUP_DIR="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      usage
      ;;
  esac
done

# Function to backup a partition
backup_partition() {
  local part=$1
  local name=$2
  local bs=$3
  
  if [[ ! -b $part ]]; then
    log_error "Partition $part does not exist!"
    return 1
  fi
  
  log_info "Backing up partition $part as $name..."
  dd_with_progress "$part" "$BACKUP_DIR/$name.img" "Backing up $name" $bs
  
  # Create hash for verification
  cd "$BACKUP_DIR"
  sha256sum "$name.img" >> checksums.sha256
}

# Main function
main() {
  log_step "Starting RG35XX H SD card backup"
  
  # Detect device if not specified
  if [[ -z "$DEVICE" ]]; then
    detect_device
    DEVICE="$TARGET_DISK"
  fi
  
  # Verify device exists and is a block device
  if [[ ! -b "$DEVICE" ]]; then
    log_error "Device $DEVICE does not exist or is not a block device"
    exit 1
  fi
  
  log_info "Target device: $DEVICE"
  
  # Show partition info
  log_info "Partition information:"
  lsblk -o NAME,MAJ:MIN,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$DEVICE" || true
  
  # Confirm with user
  log_warn "WARNING: This will read all partitions from $DEVICE"
  read -p "Continue with backup? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    log_info "Backup cancelled by user"
    exit 0
  fi
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR"
  log_info "Backing up to: $BACKUP_DIR"
  
  # Unmount any partitions
  log_info "Unmounting partitions..."
  for part in "$DEVICE"*; do
    if [[ -b "$part" ]]; then
      umount "$part" 2>/dev/null || true
    fi
  done
  
  # Backup GPT partition table
  log_info "Backing up GPT partition table..."
  sgdisk --backup="$BACKUP_DIR/gpt-backup.bin" "$DEVICE" || log_warn "GPT backup failed"
  
  # Get partition table info
  log_info "Saving partition information..."
  parted -s "$DEVICE" unit s print > "$BACKUP_DIR/partition-table.txt" || log_warn "Could not save partition table"
  
  # Backup important partitions
  # Assuming p4 is boot and p5 is root
  BOOT_PART="${DEVICE}4"
  ROOT_PART="${DEVICE}5"
  
  backup_partition "$BOOT_PART" "boot-p4-backup" "4M"
  
  # Do we want a full backup of the root partition?
  read -p "Create full backup of root partition (may be large)? (yes/no): " backup_root
  if [[ "$backup_root" == "yes" ]]; then
    backup_partition "$ROOT_PART" "rootfs-p5-backup" "4M"
  else
    # Mount and backup just kernel modules
    log_info "Creating selective backup of kernel modules..."
    local tmp_mount="/tmp/rg35xx_rootfs_backup"
    mkdir -p "$tmp_mount"
    mount "$ROOT_PART" "$tmp_mount" || { 
      log_warn "Could not mount rootfs for selective backup"
      umount "$tmp_mount" 2>/dev/null
    }
    
    if [[ -d "$tmp_mount/lib/modules" ]]; then
      log_info "Backing up kernel modules..."
      tar -czf "$BACKUP_DIR/modules-backup.tar.gz" -C "$tmp_mount" lib/modules
      cd "$BACKUP_DIR"
      sha256sum "modules-backup.tar.gz" >> checksums.sha256
    fi
    
    umount "$tmp_mount" 2>/dev/null
    rmdir "$tmp_mount" 2>/dev/null
  fi
  
  # Final verification
  log_success "Backup completed successfully!"
  log_info "Backup location: $BACKUP_DIR"
  log_info "Files:"
  ls -lh "$BACKUP_DIR"
  
  # Instructions for restore
  echo
  log_info "To restore the GPT partition table:"
  echo "  sudo sgdisk --load-backup=\"$BACKUP_DIR/gpt-backup.bin\" $DEVICE"
  echo
  log_info "To restore the boot partition:"
  echo "  sudo dd if=\"$BACKUP_DIR/boot-p4-backup.img\" of=$BOOT_PART bs=4M conv=fsync"
  echo
  if [[ "$backup_root" == "yes" ]]; then
    log_info "To restore the root partition:"
    echo "  sudo dd if=\"$BACKUP_DIR/rootfs-p5-backup.img\" of=$ROOT_PART bs=4M conv=fsync"
  else
    log_info "To restore kernel modules:"
    echo "  sudo mount $ROOT_PART /mnt/rootfs"
    echo "  sudo tar -xzf \"$BACKUP_DIR/modules-backup.tar.gz\" -C /mnt/rootfs"
    echo "  sudo umount /mnt/rootfs"
  fi
}

# Run main function
main "$@"

