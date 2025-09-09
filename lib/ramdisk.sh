#!/bin/bash
# Shared ramdisk extraction utility

extract_ramdisk() {
    local stock_boot_img="$1"   # path to stock boot image (p4 dump)
    local out_ramdisk="$2"      # desired output ramdisk .cpio.gz

    if [[ -f "$out_ramdisk" ]]; then
        log_info "Ramdisk already present: $out_ramdisk"
        return 0
    fi
    if [[ ! -f "$stock_boot_img" ]]; then
        log_warn "Stock boot image not found: $stock_boot_img"
        return 1
    fi

    local tmp
    tmp=$(mktemp -d)
    pushd "$tmp" >/dev/null || return 1

    local extracted=0
    if command -v magiskboot >/dev/null 2>&1; then
        log_info "Using magiskboot to unpack ramdisk"
        magiskboot unpack "$stock_boot_img" && {
            if [[ -f ramdisk.cpio.gz ]]; then
                cp ramdisk.cpio.gz "$out_ramdisk"; extracted=1
            elif [[ -f ramdisk.cpio ]]; then
                gzip -c ramdisk.cpio > "$out_ramdisk"; extracted=1
            fi
        }
    fi
    if (( ! extracted )) && command -v unmkbootimg >/dev/null 2>&1; then
        log_info "Using unmkbootimg to unpack ramdisk"
        unmkbootimg -i "$stock_boot_img" >/dev/null 2>&1 || true
        local gz
        gz=$(ls -1 *.gz 2>/dev/null | head -n1 || true)
        if [[ -n "$gz" ]]; then cp "$gz" "$out_ramdisk"; extracted=1; fi
    fi
    if (( ! extracted )) && command -v abootimg >/dev/null 2>&1; then
        log_info "Using abootimg to extract ramdisk"
        abootimg -x "$stock_boot_img" >/dev/null 2>&1 || true
        local initrd
        initrd=$(ls -1 initrd.img-* 2>/dev/null | head -n1 || true)
        if [[ -n "$initrd" ]]; then cp "$initrd" "$out_ramdisk"; extracted=1; fi
    fi

    popd >/dev/null || true
    rm -rf "$tmp"

    if (( extracted )); then
        log_success "Extracted ramdisk -> $out_ramdisk"
        return 0
    fi

    log_warn "Failed to extract ramdisk; creating minimal placeholder"
    local mtmp
    mtmp=$(mktemp -d)
    (cd "$mtmp" && echo '#!/bin/sh' > init && chmod +x init && find . | cpio -H newc -o 2>/dev/null | gzip > "$out_ramdisk")
    rm -rf "$mtmp"
    log_info "Created minimal ramdisk placeholder"
    return 0
}
