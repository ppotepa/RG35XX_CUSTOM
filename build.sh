#!/bin/bash
# Main build orchestrator for RG35XX_H Custom Linux Builder

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules
source "$SCRIPT_DIR/config/constants.sh"
source "$SCRIPT_DIR/lib/logger.sh" 
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/device.sh"
source "$SCRIPT_DIR/builders/kernel_builder.sh"
source "$SCRIPT_DIR/builders/busybox_builder.sh"
source "$SCRIPT_DIR/builders/rootfs_builder.sh"
source "$SCRIPT_DIR/flash/flasher.sh"

# Cleanup on exit
trap 'cleanup_build' EXIT

show_header() {
    echo -e "${GREEN}"
    echo "=================================="
    echo "  RG35XX_H Custom Linux Builder"  
    echo "=================================="
    echo -e "${NC}"
}

run_full_build() {
    show_header
    check_root
    check_dependencies
    detect_sd_card
    setup_build_environment
    
    get_linux_source
    configure_kernel
    build_kernel
    
    # Save kernel image
    mkdir -p "$SCRIPT_DIR/out"
    cp "$BUILD_DIR/out/zImage-dtb" "$SCRIPT_DIR/out/" 2>/dev/null || true
    
    get_busybox_source
    build_busybox
    create_rootfs
    flash_device
    
    step "Build Complete!"
    log "Remove SD card and insert into RG35XX_H to boot custom Linux"
    log "Backup files saved as backup_boot.img and backup_rootfs.img"
}

run_flash_only() {
    check_root
    setup_build_environment
    detect_sd_card
    mkdir -p "$BUILD_DIR/out"
    
    # Find existing kernel image
    local zimage_path=""
    for possible_path in "$SCRIPT_DIR/out/zImage-dtb" "$SCRIPT_DIR/zImage-dtb" "$BUILD_DIR/out/zImage-dtb"; do
        if [[ -f "$possible_path" ]]; then
            zimage_path="$possible_path"
            log "Found kernel image at: $zimage_path"
            break
        fi
    done
    
    if [[ -z "$zimage_path" ]]; then
        error "No existing kernel image found. Run full build first or specify path."
    fi
    
    log "Using kernel image: $zimage_path"
    if [[ "$zimage_path" != "$BUILD_DIR/out/zImage-dtb" ]]; then
        cp "$zimage_path" "$BUILD_DIR/out/zImage-dtb"
    fi
    
    flash_device
    step "Flashing Complete!"
    log "Remove SD card and insert into RG35XX_H to boot custom Linux"
}

run_partial_build() {
    local start_step="$1"
    
    check_root
    setup_build_environment
    
    case $start_step in
        modules)
            rsync -a --exclude='.git' "$SCRIPT_DIR/linux/" "$BUILD_DIR/linux/"
            cd "$BUILD_DIR/linux"
            install_kernel_modules
            get_busybox_source
            build_busybox
            create_rootfs
            detect_sd_card
            flash_device
            ;;
        busybox)
            mkdir -p "$BUILD_DIR/rootfs" "$BUILD_DIR/out"
            get_busybox_source
            build_busybox
            create_rootfs
            detect_sd_card
            flash_device
            ;;
        rootfs)
            mkdir -p "$BUILD_DIR/rootfs" "$BUILD_DIR/out"
            create_rootfs
            detect_sd_card
            flash_device
            ;;
        *)
            error "Unknown start step: $start_step"
            ;;
    esac
    
    step "Build Complete!"
    log "Remove SD card and insert into RG35XX_H to boot custom Linux"
    log "Backup files saved as backup_boot.img and backup_rootfs.img"
}

parse_arguments() {
    START_STEP="all"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup) SKIP_BACKUP=1 ;;
            --interactive) INTERACTIVE=1 ;;
            --start-from)
                shift
                START_STEP="$1"
                ;;
            --help) 
                show_help
                exit 0 ;;
            *) error "Unknown option: $1" ;;
        esac
        shift
    done
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-backup     Skip creating backup of original firmware"
    echo "  --interactive     Ask for confirmation before flashing"
    echo "  --start-from STEP Start from a specific step: modules, busybox, rootfs, flash"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full build and flash"
    echo "  $0 --interactive      # Full build with confirmation prompts"
    echo "  $0 --start-from flash # Just flash existing kernel"
    echo "  $0 --skip-backup      # Build without creating backups"
}

main() {
    parse_arguments "$@"
    
    case $START_STEP in
        all) 
            run_full_build 
            ;;
        flash) 
            run_flash_only 
            ;;
        modules|busybox|rootfs) 
            run_partial_build "$START_STEP" 
            ;;
        *) 
            error "Unknown start step: $START_STEP" 
            ;;
    esac
}

# Run main function with all arguments
main "$@"
