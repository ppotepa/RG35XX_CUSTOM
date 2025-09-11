#!/bin/bash
# Configure kernel boot arguments for LCD/HDMI console on RG35HAXX (Linux path)

# Guard against multiple sourcing
[[ -n "${RG35HAXX_BOOTARG_LOADED:-}" ]] && return 0
export RG35HAXX_BOOTARG_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"

setup_console_bootargs() {
    log_step "Configuring LCD console bootargs for RG35XX-H"
    
    # Detect root partition if not already set
    if [[ -z "${ROOT_PART:-}" ]]; then
        log_info "Detecting RG35XX-H root partition..."
        for dev in /dev/sd[a-z] /dev/mmcblk[0-9]; do
            [[ -b "$dev" ]] || continue
            
            # Check partitions 4 and 5 (standard RG35XX layout)
            if [[ "$dev" =~ /dev/sd[a-z] ]]; then
                local root_candidate="${dev}5"
            else
                local root_candidate="${dev}p5"
            fi
            
            if [[ -b "$root_candidate" ]]; then
                # Check if this is ~7GB partition
                local root_size=$(lsblk -bno SIZE "$root_candidate" 2>/dev/null)
                if [[ -n "$root_size" ]]; then
                    local root_gb=$((root_size / 1024 / 1024 / 1024))
                    if [[ $root_gb -ge 6 && $root_gb -le 8 ]]; then
                        ROOT_PART="$root_candidate"
                        log_info "Detected root partition: $ROOT_PART (${root_gb}GB)"
                        break
                    fi
                fi
            fi
        done
        
        # Fallback to /dev/sdc5 based on user's lsblk output
        if [[ -z "${ROOT_PART:-}" ]]; then
            ROOT_PART="/dev/sdc5"
            log_warn "Could not auto-detect, using default: $ROOT_PART"
        fi
    fi
    
    # Research-backed kernel command line for RG35XX-H LCD console
    # Based on Knulli project and successful community implementations
    local console_args="console=tty0 loglevel=7 ignore_loglevel"
    local root_args="root=$ROOT_PART rw rootwait"
    local fb_args="fbcon=map:1 fbcon=nodefer video=640x480-32 vt.global_cursor_default=0"
    
    # Final kernel cmdline
    export CUSTOM_CMDLINE="$root_args $console_args $fb_args"
    
    log_info "Root partition: $ROOT_PART"
    log_info "Kernel cmdline: $CUSTOM_CMDLINE"
    log_success "RG35XX-H LCD console bootargs configured"
    
    return 0
}

# Alias for compatibility with existing code
modify_bootargs() {
    setup_console_bootargs
}
