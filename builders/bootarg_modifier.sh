#!/bin/bash
# Configure kernel boot arguments for LCD/HDMI console on RG35HAXX (Linux path)

# Guard against multiple sourcing
[[ -n "${RG35HAXX_BOOTARG_LOADED:-}" ]] && return 0
export RG35HAXX_BOOTARG_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"

setup_console_bootargs() {
    log_step "Configuring LCD console bootargs"
    
    # Notes:
    # - No UART available: do NOT add console=ttyS0
    # - Prefer tty0 so fbcon will take over on the first DRM fb
    # - Provide sane root args for SD card with PARTLABEL=rootfs
    # - Enable verbose logs initially to help bring-up without UART
    # - Allow HDMI as a fallback/output mirror when connected

    # Core console/root args
    local console_args="console=tty0 loglevel=7 ignore_loglevel panic=10"
    local root_args="root=PARTLABEL=rootfs rootfstype=ext4 rootwait init=/init"

    # fb/DRM helpers for on-screen console
    local fb_args="fbcon=map:1 fbcon=font:SUN8x16 vt.global_cursor_default=0 drm_kms_helper.drm_fbdev_overalloc=100"

    # Optional HDMI mode as a helper (doesn't break LCD; used if HDMI is present)
    # If this causes issues on some panels, set to video=HDMI-A-1:D to disable
    local video_args="video=HDMI-A-1:1280x720@60"

    # Final kernel cmdline (Linux path uses CUSTOM_CMDLINE)
    export CUSTOM_CMDLINE="$console_args $root_args $fb_args $video_args quiet splash"
    
    log_info "Kernel cmdline: $CUSTOM_CMDLINE"
    log_success "LCD console bootargs configured"
    
    return 0
}

# Alias for compatibility with existing code
modify_bootargs() {
    setup_console_bootargs
}
