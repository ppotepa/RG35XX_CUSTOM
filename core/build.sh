#!/bin/bash
# RG35HAXX Custom Linux Builder - Main Orchestrator (Fixed Version)

set -euo pipefail

# Get absolute script directory
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
export SCRIPT_DIR

# Early help function (before logger is loaded)
show_early_help() {
    cat << 'EOF'
RG35HAXX Custom Linux Builder

Usage: $0 [OPTIONS]

Options:
  --skip-build      Skip kernel build, flash existing files (still builds BusyBox if needed)
  --force-build     Force rebuild even if output exists
  --skip-sd-check   Skip SD card validation at startup
  --skip-backup     Skip SD card backup before flashing (faster)
    --dtb=N           Select DTB variant (0=rg35xx-h, 1=rg35xx-h-rev6, 2=rg40xx-h)
    --package=MODE    Boot image packaging mode (catdt or with-dt)
    --cmdline=STR     Override kernel command line (forces unless --no-force-cmdline used)
    --pagesize=N      Override boot image page size (default 2048)
    --no-force-cmdline  Do not set CONFIG_CMDLINE_FORCE (allow bootloader append)
  --help, -h        Show this help message

Examples:
  sudo ./run_ubuntu.sh                           # Full build with SD validation
  sudo ./run_ubuntu.sh --skip-build             # Flash existing build (with backup)
  sudo ./run_ubuntu.sh --skip-build --skip-backup  # Fast flash existing build
  sudo ./run_ubuntu.sh --dtb=1 --package=with-dt   # Try alternate DTB and packaging mode
  sudo ./run_ubuntu.sh --skip-sd-check          # Build without requiring SD card
  sudo ./run_ubuntu.sh --force-build            # Force complete rebuild
EOF

    # Advanced tools reference
    echo
    echo "Advanced Tools:"
    echo "  ./plugins/verification/build_verification.sh    # Build output validation & reporting"
    echo "  ./plugins/sd_tools/advanced_sd_tools.sh         # SD diagnostics, backup, recovery, optimization"
    echo "  ./plugins/verification/automated_testing.sh     # Automated testing & integration checks"
    echo "  ./tools/dev_tools.sh                           # Developer workflow utilities"
    echo "  ./tools/fix_boot_image.sh                      # Manual boot image page size fix"
    echo "  ./plugins/backup/restore_backups.sh            # Restore from backup"
    echo "  ./core/install_dependencies.sh                 # Install all required build tools"
    echo
    echo "See README.md and ADVANCED_FEATURES_COMPLETE.md for full documentation."
}

# Parse command line arguments (before sourcing logger to avoid issues)
SKIP_BUILD=false
FORCE_BUILD=false
SKIP_SD_CHECK=false
SKIP_BACKUP=false
DTB_INDEX=0
PACKAGE_MODE="catdt"
CUSTOM_CMDLINE="${CUSTOM_CMDLINE:-}"
PAGE_SIZE_OVERRIDE=""
NO_FORCE_CMDLINE="false"
FULL_VERIFY="false"

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
        --dtb=*)
            DTB_INDEX="${1#*=}"
            if ! [[ "$DTB_INDEX" =~ ^[0-2]$ ]]; then
                echo "ERROR: DTB index must be 0, 1, or 2" >&2
                exit 1
            fi
            shift
            ;;
        --package=*)
            PACKAGE_MODE="${1#*=}"
            if [[ "$PACKAGE_MODE" != "catdt" && "$PACKAGE_MODE" != "with-dt" ]]; then
                echo "ERROR: Package mode must be 'catdt' or 'with-dt'" >&2
                exit 1
            fi
            shift
            ;;
        --cmdline=*)
            CUSTOM_CMDLINE="${1#*=}"
            shift
            ;;
        --pagesize=*)
            PAGE_SIZE_OVERRIDE="${1#*=}"
            if ! [[ "$PAGE_SIZE_OVERRIDE" =~ ^[0-9]+$ ]]; then
                echo "ERROR: pagesize must be numeric" >&2; exit 1;
            fi
            shift
            ;;
        --no-force-cmdline)
            NO_FORCE_CMDLINE="true"; shift ;;
        --full-verify)
            FULL_VERIFY="true"; shift ;;
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

export SKIP_BUILD FORCE_BUILD SKIP_SD_CHECK SKIP_BACKUP DTB_INDEX PACKAGE_MODE CUSTOM_CMDLINE PAGE_SIZE_OVERRIDE NO_FORCE_CMDLINE FULL_VERIFY

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
    if [[ -d "${TEMP_BUILD_DIR:-}" ]]; then
        log_info "Cleaning up temporary directory..."
        rm -rf "$TEMP_BUILD_DIR"
    fi
    # Note: We keep the main build directory since it's in the project folder
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
    echo "  --skip-build      Skip kernel build, flash existing files (still builds BusyBox if needed)"
    echo "  --force-build     Force rebuild even if output exists"
    echo "  --skip-sd-check   Skip SD card validation at startup"
    echo "  --skip-backup     Skip SD card backup before flashing (faster)"
    echo "    --full-verify     After flashing compute full SHA256 of boot partition (slow)"
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

# Create a minimal rootfs when we have an existing kernel but no rootfs
create_minimal_rootfs() {
    log_step "Creating minimal rootfs from existing kernel"
    start_progress "rootfs" 100
    
    # Copy existing kernel
    update_progress 10 "Preparing build environment..."
    mkdir -p "$TEMP_BUILD_DIR/out" || { log_error "Failed to create temp directory"; return 1; }
    cp "$OUTPUT_DIR/zImage-dtb" "$TEMP_BUILD_DIR/out/" || { log_error "Failed to copy kernel image"; return 1; }
    
    # Create minimal rootfs with busybox
    update_progress 30 "Getting BusyBox source..."
    if [[ ! -d "$SCRIPT_DIR/busybox" ]]; then
        get_busybox_source || { log_error "Failed to get BusyBox source"; end_progress "Failed"; return 1; }
        update_progress 50 "Configuring BusyBox..."
        configure_busybox || { log_error "Failed to configure BusyBox"; end_progress "Failed"; return 1; }
        update_progress 60 "Building BusyBox..."
        build_busybox || { log_error "Failed to build BusyBox"; end_progress "Failed"; return 1; }
    fi
    
    update_progress 80 "Creating rootfs..."
    create_rootfs || { log_error "Failed to create rootfs"; end_progress "Failed"; return 1; }
    update_progress 100 "Rootfs created"
    
    end_progress "✅ Created minimal rootfs from existing kernel"
    return 0
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
    
    # Set active DTB from index
    ACTIVE_DTB="${DTB_VARIANTS[$DTB_INDEX]}"
    log_info "DTB variant: $ACTIVE_DTB (index: $DTB_INDEX)"
    log_info "Packaging mode: $PACKAGE_MODE"
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
        
        # Check for minimum required files
        if [[ -f "$OUTPUT_DIR/zImage-dtb" ]]; then
            KERNEL_FOUND=true
            log_success "✅ Found kernel image ($(du -h "$OUTPUT_DIR/zImage-dtb" | cut -f1))"
        else
            KERNEL_FOUND=false
            log_warn "⚠️ Kernel image not found!"
        fi
        
        if [[ -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
            ROOTFS_FOUND=true
            log_success "✅ Found rootfs ($(du -h "$OUTPUT_DIR/rootfs.tar.gz" | cut -f1))"
        else
            ROOTFS_FOUND=false
            log_warn "⚠️ Rootfs archive not found - will build minimal rootfs"
        fi
        
        # Always ensure BusyBox is available, even with --skip-build
        log_step "Ensuring BusyBox is available (required for rootfs)"
        setup_build_environment
        
        # Always build BusyBox if it doesn't exist
        if [[ ! -d "$BUILD_DIR/busybox" ]] || [[ ! -f "$BUILD_DIR/busybox/busybox" ]]; then
            log_info "BusyBox not found - building it now..."
            get_busybox_source || { log_error "Failed to get BusyBox source"; exit 1; }
            configure_busybox || { log_error "Failed to configure BusyBox"; exit 1; }
            build_busybox || { log_error "Failed to build BusyBox"; exit 1; }
            log_success "✅ BusyBox build completed"
        else
            log_success "✅ BusyBox already available"
        fi

        # Allow partial skip if at least kernel is found
        if [[ "$KERNEL_FOUND" == "true" ]]; then
            # Create minimal rootfs if needed
            if [[ "$ROOTFS_FOUND" == "false" ]]; then
                log_info "Creating minimal rootfs using existing kernel..."
                # Build minimal rootfs with existing kernel
                mkdir -p "$TEMP_BUILD_DIR"
                create_minimal_rootfs || { log_error "Failed to create minimal rootfs"; exit 1; }
            fi
        else
            log_error "Cannot skip build - no usable kernel image found!"
            log_info "Available files in $OUTPUT_DIR:"
            ls -la "$OUTPUT_DIR/" 2>/dev/null || log_info "  (output directory doesn't exist)"
            log_info "Run without --skip-build to create the files first."
            exit 1
        fi
        
        # Copy outputs to temp build directory for flashing
        # Files are already in OUTPUT_DIR, no need to copy
        log_info "Build outputs ready for flashing"
    else
        # Full build process
        log_step "Starting full build process"

        # Ensure a clean output directory when performing a full build
        if [[ -d "$OUTPUT_DIR" ]]; then
            log_info "Removing existing build output directory for clean build: $OUTPUT_DIR"
            rm -rf "$OUTPUT_DIR" || { log_warn "Failed to remove $OUTPUT_DIR"; }
        fi
        
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
            # Files are already in OUTPUT_DIR, no need to copy
            log_info "Using existing build outputs"
        else
            # Setup build environment
            setup_build_environment
            
            # Initialize overall progress tracking
            log_step "Starting RG35HAXX build process"
            start_progress "overall" 100
            
            # Build process
            log_step "Building Linux kernel"
            update_progress 10 "Getting Linux kernel source..."
            get_linux_source || { log_error "Failed to get Linux source"; exit 1; }
            # Compute LCD/HDMI console bootargs BEFORE configuring kernel so CONFIG_CMDLINE is correct
            source "$SCRIPT_DIR/builders/bootarg_modifier.sh"
            update_progress 15 "Preparing bootargs..."
            modify_bootargs || { log_error "Failed to modify bootargs"; exit 1; }

            update_progress 18 "Configuring kernel..."
            configure_kernel || { log_error "Failed to configure kernel"; exit 1; }

            update_progress 25 "Building kernel..."
            build_kernel || { log_error "Failed to build kernel"; exit 1; }
            update_progress 40 "Kernel build complete"
            log_success "✅ Kernel build completed successfully"
            
            log_step "Building BusyBox userspace"
            update_progress 45 "Getting BusyBox source..."
            get_busybox_source || { log_error "Failed to get BusyBox source"; exit 1; }
            update_progress 50 "Configuring BusyBox..."
            configure_busybox || { log_error "Failed to configure BusyBox"; exit 1; }
            update_progress 55 "Building BusyBox..."
            build_busybox || { log_error "Failed to build BusyBox"; exit 1; }
            update_progress 65 "BusyBox build complete"
            log_success "✅ BusyBox build completed successfully"
            
            log_step "Creating root filesystem"
            update_progress 70 "Creating rootfs..."
            create_rootfs || { log_error "Failed to create rootfs"; exit 1; }
            update_progress 80 "Root filesystem created"
            log_success "✅ Root filesystem created successfully"
            
            # Save outputs to persistent directory
            log_step "Saving build outputs"
            update_progress 85 "Saving build outputs..."
            # Outputs are already saved directly to OUTPUT_DIR during build
            update_progress 90 "Build outputs saved"
            log_success "Build outputs available in $OUTPUT_DIR"
            
            end_progress "Build completed successfully"
        fi
    fi
    
    # Flash to device
    if [[ "$SKIP_SD_CHECK" == "false" ]]; then
        log_step "Flashing to SD card"
        start_progress "overall" 100
        update_progress 95 "Flashing to SD card..."
        flash_device
        update_progress 100 "Flash complete"
        end_progress "All operations completed"
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

