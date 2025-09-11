#!/bin/bash
# Main entry point for RG35XX-H Custom Linux Builder
# This script loads the plugin architecture and dispatches to appropriate modules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and libraries
source "$SCRIPT_DIR/config/constants.sh"
source "$SCRIPT_DIR/lib/logger.sh"
# Initialize logging early so child scripts inherit LOG_FILE and functions
init_logging

# Display banner
echo "=================================================================="
echo -e "\033[1;32m  RG35XX-H Custom Linux Builder\033[0m"
echo -e "\033[1;36m  Plugin-Based Architecture\033[0m"
echo "=================================================================="

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model=*)
            MODEL_NAME="${1#*=}"
            shift
            ;;
        --rg35xxh)
            MODEL_NAME="rg35xxh"; shift ;;
        --build)
            # Run the build process (source to preserve environment and functions)
            source "$SCRIPT_DIR/core/build.sh"
            exit $?
            ;;
        --build-rg35xxh)
            # Run the specialized RG35XX-H build process
            bash "$SCRIPT_DIR/core/build_rg35xxh.sh"
            exit $?
            ;;
        --install-deps)
            # Install dependencies
            bash "$SCRIPT_DIR/core/install_dependencies.sh"
            exit $?
            ;;
        --backup)
            # Backup SD card
            bash "$SCRIPT_DIR/plugins/backup/backup_sd.sh"
            exit $?
            ;;
        --restore)
            # Restore SD card
            bash "$SCRIPT_DIR/plugins/backup/restore_backups.sh"
            exit $?
            ;;
        --diagnose)
            # Run diagnostics
            bash "$SCRIPT_DIR/plugins/diagnostics/sd_diagnostics.sh"
            exit $?
            ;;
        --verify)
            # Run build verification
            bash "$SCRIPT_DIR/plugins/verification/build_verification.sh"
            exit $?
            ;;
        --help|-h)
            echo "Usage: $0 [option]"
            echo "Options:"
            echo "  --build             Run the standard build process"
            echo "  --build-rg35xxh     Run the specialized RG35XX-H build process"
            echo "  --install-deps      Install required dependencies"
            echo "  --backup            Backup the SD card"
            echo "  --restore           Restore the SD card from backup"
            echo "  --diagnose          Run SD card diagnostics"
            echo "  --verify            Run build verification"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# If no arguments provided, show help
echo "No action specified. Use --help for usage information."
echo "Running default build process..."
source "$SCRIPT_DIR/core/build.sh"
