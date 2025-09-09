#!/bin/bash
# RG35HAXX Custom Linux Builder - Main Orchestrator (Fixed Version)

set -euo pipefail

# Get absolute script directory
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
export SCRIPT_DIR

# Early help function (before logger is loaded)
show_early_help() {
    cat << 'EOF'
RG35HAXX Custom Linux Builder

Usage: $0 [OPTIONS]

Options:
  --skip-build      Skip kernel/rootfs build, flash existing files only
  --force-build     Force rebuild even if output exists
  --skip-sd-check   Skip SD card validation at startup
  --skip-backup     Skip SD card backup before flashing (faster)
  --help, -h        Show this help message

Examples:
  sudo ./run_ubuntu.sh                           # Full build with SD validation
  sudo ./run_ubuntu.sh --skip-build             # Flash existing build (with backup)
  sudo ./run_ubuntu.sh --skip-build --skip-backup  # Fast flash existing build
  sudo ./run_ubuntu.sh --skip-sd-check          # Build without requiring SD card
  sudo ./run_ubuntu.sh --force-build            # Force complete rebuild
EOF
}

# Parse command line arguments (before sourcing logger to avoid issues)
SKIP_BUILD=false
FORCE_BUILD=false
SKIP_SD_CHECK=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --force-build)
            FORCE_BUILD=true
            shift
            ;;
        --skip-sd-check)
            SKIP_SD_CHECK=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --help|-h)
            show_early_help
            exit 0
            ;;
        clear)
            # Ignore 'clear' argument (commonly added by mistake)
            shift
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

export SKIP_BUILD FORCE_BUILD SKIP_SD_CHECK SKIP_BACKUP

# Now source all modules safely
echo "Loading configuration..."
source "$SCRIPT_DIR/config/constants.sh" || { echo "ERROR: Failed to load constants"; exit 1; }

echo "Loading logger..."
source "$SCRIPT_DIR/lib/logger.sh" || { echo "ERROR: Failed to load logger"; exit 1; }

echo "Loading system utilities..."
source "$SCRIPT_DIR/lib/system.sh" || { echo "ERROR: Failed to load system utilities"; exit 1; }

echo "Loading device management..."
source "$SCRIPT_DIR/lib/device.sh" || { echo "ERROR: Failed to load device management"; exit 1; }

echo "Loading builders..."
source "$SCRIPT_DIR/builders/kernel_builder.sh" || { echo "ERROR: Failed to load kernel builder"; exit 1; }
source "$SCRIPT_DIR/builders/busybox_builder.sh" || { echo "ERROR: Failed to load busybox builder"; exit 1; }
source "$SCRIPT_DIR/builders/rootfs_builder.sh" || { echo "ERROR: Failed to load rootfs builder"; exit 1; }
source "$SCRIPT_DIR/flash/flasher.sh" || { echo "ERROR: Failed to load flasher"; exit 1; }

# Cleanup on exit
trap 'cleanup' EXIT

cleanup() {
    if [[ -d "${BUILD_DIR:-}" ]]; then
        log_info "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}

show_header() {
    echo -e "${GREEN}"
    echo "====================================="
    echo "      RG35HAXX Custom Linux Builder  "
    echo "====================================="
    echo -e "${NC}"
    echo
}

show_help() {
    echo "RG35HAXX Custom Linux Builder"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --skip-build      Skip kernel/rootfs build, flash existing files only"
    echo "  --force-build     Force rebuild even if output exists"
    echo "  --skip-sd-check   Skip SD card validation at startup"
    echo "  --skip-backup     Skip SD card backup before flashing (faster)"
    echo "  --help, -h        Show this help message"
    echo
    echo "Examples:"
    echo "  $0                           # Full build with SD validation"
    echo "  $0 --skip-build             # Flash existing build (with backup)"
    echo "  $0 --skip-build --skip-backup  # Fast flash existing build"
    echo "  $0 --skip-sd-check          # Build without requiring SD card"
    echo "  $0 --force-build            # Force complete rebuild"
    echo
}

validate_sd_card_early() {
    if [[ "$SKIP_SD_CHECK" == "true" ]]; then
        log_warn "Skipping SD card validation (--skip-sd-check specified)"
        return 0
    fi
    
    log_step "Validating SD card presence and schema"
    
    if ! detect_sd_card; then
        log_error "No valid RG35XX_H SD card detected!"
        echo
        echo "Required SD card schema:"
        echo "  - Removable device (USB/SD)"
        echo "  - Partition 1: Label 'boot' (FAT32)"
        echo "  - Partition 2: Label 'rootfs' (ext4)"
        echo
        echo "Please:"
        echo "  1. Insert a properly formatted RG35XX_H SD card"
        echo "  2. Or use --skip-sd-check to build without SD validation"
        echo
        exit 1
    fi
    
    log_success "Valid SD card detected: $TARGET_DISK"
    log_info "Boot partition: $BOOT_PART"
    log_info "Root partition: $ROOT_PART"
}

main() {
    show_header
    
    # Initialize logging with enhanced verbosity
    init_logging
    log_info "Starting RG35HAXX Custom Linux Build"
    log_info "Build mode: $([ "$SKIP_BUILD" == "true" ] && echo "FLASH-ONLY" || echo "FULL-BUILD")"
    log_info "Force rebuild: $([ "$FORCE_BUILD" == "true" ] && echo "YES" || echo "NO")"
    log_info "SD validation: $([ "$SKIP_SD_CHECK" == "true" ] && echo "SKIPPED" || echo "REQUIRED")"
    log_info "Backup mode: $([ "$SKIP_BACKUP" == "true" ] && echo "SKIPPED" || echo "ENABLED")"
    echo
    
    # Check prerequisites
    check_root
    check_dependencies || exit 1
    check_build_environment || exit 1
    
    # Early SD card validation (unless skipped)
    validate_sd_card_early
    
    # Detect and configure device
    detect_device
    configure_device_specific_settings
    
    # Skip build if requested
    if [[ "$SKIP_BUILD" == "true" ]]; then
        log_step "Skipping build phase (--skip-build specified)"
        
        # Check if persistent build outputs exist
        if [[ ! -f "$OUTPUT_DIR/zImage-dtb" ]] || [[ ! -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
            log_error "Build outputs not found in $OUTPUT_DIR!"
            log_info "Available files:"
            ls -la "$OUTPUT_DIR/" 2>/dev/null || log_info "  (output directory doesn't exist)"
            log_info "Run without --skip-build to create the files first."
            exit 1
        fi
        
        log_success "Using existing build outputs:"
        log_info "  Kernel: $OUTPUT_DIR/zImage-dtb ($(stat -c%s "$OUTPUT_DIR/zImage-dtb" | numfmt --to=iec))"
        log_info "  RootFS: $OUTPUT_DIR/rootfs.tar.gz ($(stat -c%s "$OUTPUT_DIR/rootfs.tar.gz" | numfmt --to=iec))"
        
        # Copy outputs to temp build directory for flashing
        setup_build_environment
        cp "$OUTPUT_DIR/zImage-dtb" "$BUILD_DIR/out/"
        cp "$OUTPUT_DIR/rootfs.tar.gz" "$BUILD_DIR/out/"
        log_info "Copied outputs to build directory for flashing"
    else
        # Full build process
        log_step "Starting full build process"
        
        # Check if we should force rebuild
        if [[ "$FORCE_BUILD" == "false" ]] && [[ -f "$OUTPUT_DIR/zImage-dtb" ]] && [[ -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
            log_warn "Build outputs already exist in $OUTPUT_DIR"
            log_info "  Kernel: $(stat -c%s "$OUTPUT_DIR/zImage-dtb" | numfmt --to=iec)"
            log_info "  RootFS: $(stat -c%s "$OUTPUT_DIR/rootfs.tar.gz" | numfmt --to=iec)"
            read -p "Continue with existing build? [Y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                log_info "Build cancelled by user"
                exit 0
            fi
            # Copy existing files to build directory
            setup_build_environment
            cp "$OUTPUT_DIR/zImage-dtb" "$BUILD_DIR/out/"
            cp "$OUTPUT_DIR/rootfs.tar.gz" "$BUILD_DIR/out/"
            log_info "Using existing build outputs"
        else
            # Setup build environment
            setup_build_environment
            
            # Build process
            log_step "Building Linux kernel"
            get_linux_source || { log_error "Failed to get Linux source"; exit 1; }
            configure_kernel || { log_error "Failed to configure kernel"; exit 1; }
            
            # Apply LCD console bootargs
            source "$SCRIPT_DIR/builders/bootarg_modifier.sh"
            modify_bootargs || { log_error "Failed to modify bootargs"; exit 1; }
            
            build_kernel || { log_error "Failed to build kernel"; exit 1; }
            log_success "✅ Kernel build completed successfully"
            
            log_step "Building BusyBox userspace"
            get_busybox_source || { log_error "Failed to get BusyBox source"; exit 1; }
            configure_busybox || { log_error "Failed to configure BusyBox"; exit 1; }
            build_busybox || { log_error "Failed to build BusyBox"; exit 1; }
            log_success "✅ BusyBox build completed successfully"
            
            log_step "Creating root filesystem"
            create_rootfs || { log_error "Failed to create rootfs"; exit 1; }
            log_success "✅ Root filesystem created successfully"
            
            # Save outputs to persistent directory
            log_step "Saving build outputs"
            mkdir -p "$OUTPUT_DIR"
            cp "$BUILD_DIR/out/zImage-dtb" "$OUTPUT_DIR/"
            cp "$BUILD_DIR/out/rootfs.tar.gz" "$OUTPUT_DIR/"
            log_success "Build outputs saved to $OUTPUT_DIR"
        fi
    fi
    
    # Flash to device
    if [[ "$SKIP_SD_CHECK" == "false" ]]; then
        log_step "Flashing to SD card"
        flash_device
    else
        log_warn "SD card validation was skipped - manual flashing required"
        log_info "Build outputs available at:"
        log_info "  Kernel: $OUTPUT_DIR/zImage-dtb"
        log_info "  RootFS: $OUTPUT_DIR/rootfs.tar.gz"
    fi
    
    log_success "RG35HAXX Build Complete!"
    log_info "Total build time: $(date -d@$SECONDS -u +%H:%M:%S)"
    log_info "Persistent outputs: $OUTPUT_DIR"
    log_info "Remove SD card and insert into RG35HAXX to boot custom Linux"
}

# Run main function
main "$@"
