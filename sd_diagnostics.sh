#!/bin/bash
# RG35XX H SD Card Diagnostics Tool
# This script helps inspect the partition table and boot image

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# Source required modules
source "$SCRIPT_DIR/lib/logger.sh" || { echo "ERROR: Failed to load logger"; exit 1; }
source "$SCRIPT_DIR/lib/device.sh" || { echo "ERROR: Failed to load device management"; exit 1; }

usage() {
  echo "RG35XX H SD Card Diagnostics Tool"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --device=DEVICE      SD card device (default: auto-detect)"
  echo "  --extract-boot       Extract boot image for inspection"
  echo "  --help               Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                         # Show partition info"
  echo "  $0 --device=/dev/sdc       # Inspect specific device"
  echo "  $0 --extract-boot          # Extract boot image for inspection"
  exit 1
}

# Parse arguments
DEVICE=""
EXTRACT_BOOT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --device=*)
      DEVICE="${1#*=}"
      shift
      ;;
    --extract-boot)
      EXTRACT_BOOT=true
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

# Main function
main() {
  log_step "RG35XX H SD Card Diagnostics"
  
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
  
  # Show basic device information
  log_step "Device Information"
  echo
  log_info "Block Device Information:"
  lsblk -o NAME,MAJ:MIN,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$DEVICE"
  echo
  
  log_info "Filesystem Signatures:"
  blkid "$DEVICE"*
  echo
  
  # Check GPT partition table
  log_step "Partition Table Analysis"
  echo
  log_info "Sector-based Partition Layout:"
  parted -s "$DEVICE" unit s print
  echo
  
  log_info "GPT Header Information:"
  sgdisk -p "$DEVICE"
  echo
  
  log_info "GPT Validation:"
  sgdisk -v "$DEVICE"
  echo
  
  # Boot partition analysis
  BOOT_PART="${DEVICE}4"
  if [[ -b "$BOOT_PART" ]]; then
    log_step "Boot Partition Analysis (p4)"
    echo
    
    log_info "Boot Image Type:"
    file -s "$BOOT_PART"
    echo
    
    # Check if we can analyze boot image
    if command -v abootimg >/dev/null 2>&1; then
      log_info "Boot Image Details (abootimg):"
      abootimg -i "$BOOT_PART"
      echo
      
      # Extract boot image if requested
      if [[ "$EXTRACT_BOOT" == "true" ]]; then
        log_info "Extracting boot image for inspection..."
        TMP_DIR="/tmp/rg35xx_boot_inspect"
        mkdir -p "$TMP_DIR"
        
        # Extract boot image
        dd if="$BOOT_PART" of="$TMP_DIR/boot.img" bs=4M
        
        # Unpack boot image
        cd "$TMP_DIR"
        log_info "Unpacking boot image to $TMP_DIR"
        abootimg -x "$TMP_DIR/boot.img"
        
        # Check page size
        PAGESIZE=$(grep -oP 'pagesize\s+\K\d+' "$TMP_DIR/bootimg.cfg" || echo "unknown")
        if [[ "$PAGESIZE" != "2048" ]]; then
          log_warn "Boot image has incorrect page size: $PAGESIZE (should be 2048)"
        else
          log_success "Boot image has correct page size: $PAGESIZE"
        fi
        
        # Check kernel cmdline
        CMDLINE=$(grep -oP 'cmdline\s+\K.*' "$TMP_DIR/bootimg.cfg" || echo "unknown")
        if [[ "$CMDLINE" != *"console="* ]]; then
          log_warn "Boot cmdline does not specify console: $CMDLINE"
        else
          log_success "Boot cmdline includes console setting: $CMDLINE"
        fi
        
        log_info "Extracted files:"
        ls -lh "$TMP_DIR"
        echo
        
        log_info "To examine extracted kernel:"
        echo "  cd $TMP_DIR"
      fi
    else
      log_warn "abootimg not installed, limited boot analysis available"
      log_info "Install abootimg for better boot image inspection:"
      echo "  apt-get install abootimg"
    fi
  fi
  
  # Root partition analysis
  ROOT_PART="${DEVICE}5"
  if [[ -b "$ROOT_PART" ]]; then
    log_step "Root Partition Analysis (p5)"
    echo
    
    log_info "Root Filesystem Type:"
    file -s "$ROOT_PART"
    echo
    
    # Check kernel modules if accessible
    log_info "Checking for kernel modules..."
    TMP_MOUNT="/tmp/rg35xx_root_inspect"
    mkdir -p "$TMP_MOUNT"
    
    if mount "$ROOT_PART" "$TMP_MOUNT"; then
      if [[ -d "$TMP_MOUNT/lib/modules" ]]; then
        log_info "Kernel modules found:"
        ls -la "$TMP_MOUNT/lib/modules"
        
        # Check module versions
        for dir in "$TMP_MOUNT/lib/modules"/*; do
          if [[ -d "$dir" ]]; then
            log_info "Module directory: $(basename "$dir")"
          fi
        done
      else
        log_warn "No kernel modules directory found"
      fi
      
      umount "$TMP_MOUNT"
    else
      log_warn "Could not mount root partition for inspection"
    fi
    
    rmdir "$TMP_MOUNT" 2>/dev/null
  fi
  
  log_success "Diagnostics completed"
}

# Run main function
main "$@"
