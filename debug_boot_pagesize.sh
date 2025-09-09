#!/bin/bash
# Debug script for boot image page size detection issues

set -e

source "$(dirname "${BASH_SOURCE[0]}")/lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootimg.sh"

debug_boot_image_pagesize() {
    local boot_image="$1"
    
    if [[ ! -f "$boot_image" ]]; then
        log_error "Boot image not found: $boot_image"
        exit 1
    fi
    
    log_info "=== Boot Image Page Size Debug ==="
    log_info "Testing image: $boot_image"
    
    # Test different detection methods
    log_info "1. Raw abootimg output:"
    if command -v abootimg >/dev/null 2>&1; then
        abootimg -i "$boot_image" 2>/dev/null || log_warn "abootimg failed"
    else
        log_warn "abootimg not available"
    fi
    
    log_info "2. Page size with original pattern:"
    local pagesize1=$(abootimg -i "$boot_image" 2>/dev/null | grep "Page size" | awk '{print $3}')
    log_info "Result: '${pagesize1}'"
    
    log_info "3. Page size with case-insensitive pattern:"
    local pagesize2=$(abootimg -i "$boot_image" 2>/dev/null | grep -iE "(page size|pagesize)" | awk '{print $NF}' | tr -d ':')
    log_info "Result: '${pagesize2}'"
    
    log_info "4. Alternative numeric extraction:"
    local pagesize3=$(abootimg -i "$boot_image" 2>/dev/null | grep -iE "page" | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) print $i}' | head -1)
    log_info "Result: '${pagesize3}'"
    
    log_info "5. All lines containing 'page':"
    abootimg -i "$boot_image" 2>/dev/null | grep -iE "page" || log_warn "No lines with 'page' found"
    
    log_info "6. Using file command:"
    file "$boot_image" || log_warn "file command failed"
    
    log_info "7. Hexdump of first 64 bytes (boot image header):"
    hexdump -C "$boot_image" | head -4 || log_warn "hexdump failed"
    
    log_info "8. Using verify_boot_image_page_size function:"
    if verify_boot_image_page_size "$boot_image" 2048; then
        log_success "Page size verification passed"
    else
        log_warn "Page size verification failed"
    fi
    
    log_info "=== Debug Complete ==="
}

# Check if boot image path provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <boot_image_path>"
    echo "Debug boot image page size detection"
    exit 1
fi

debug_boot_image_pagesize "$1"
