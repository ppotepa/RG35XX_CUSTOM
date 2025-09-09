#!/bin/bash
# Configure kernel boot arguments for LCD console on RG35HAXX

# Guard against multiple sourcing
[[ -n "${RG35HAXX_BOOTARG_LOADED:-}" ]] && return 0
export RG35HAXX_BOOTARG_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"

setup_console_bootargs() {
    log_step "Configuring LCD console bootargs"
    
    # LCD console configuration for RG35HAXX
    local console_args="console=tty0 fbcon=rotate:1 vt.global_cursor_default=0"
    local video_args="video=HDMI-A-1:480x320@60"
    local fb_args="drm_kms_helper.drm_fbdev_overalloc=100"
    
    # Complete kernel command line for LCD output
    export KERNEL_CMDLINE="$console_args $video_args $fb_args quiet splash"
    
    log_info "Kernel cmdline: $KERNEL_CMDLINE"
    log_success "LCD console bootargs configured"
    
    return 0
}

# Alias for compatibility with existing code
modify_bootargs() {
    setup_console_bootargs
}
