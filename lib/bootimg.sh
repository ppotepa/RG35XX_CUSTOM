#!/bin/bash
# Boot image helper utilities: extract header parameters and generate mkbootimg args

# Requires one of: abootimg | magiskboot | unmkbootimg

# Required page size for RG35XX_H device
BOOT_IMAGE_PAGE_SIZE=2048

bootimg_extract_header() {
    local img="$1"   # stock boot image path
    local out_var_prefix="$2" # prefix for global variables
    [[ -f "$img" ]] || { log_warn "bootimg_extract_header: file not found: $img"; return 1; }

    # Reset vars
    eval ${out_var_prefix}_PAGESIZE=""; eval ${out_var_prefix}_BASE=""; eval ${out_var_prefix}_BOARD="";
    eval ${out_var_prefix}_CMDLINE=""; eval ${out_var_prefix}_KERNEL_OFFSET=""; eval ${out_var_prefix}_RAMDISK_OFFSET="";
    eval ${out_var_prefix}_TAGS_OFFSET=""; eval ${out_var_prefix}_OS_VERSION=""; eval ${out_var_prefix}_OS_PATCH_LEVEL="";

    if command -v abootimg >/dev/null 2>&1; then
        local info
        info=$(abootimg -i "$img" 2>/dev/null) || true
        if [[ -n "$info" ]]; then
            local pagesize base cmdline board
            pagesize=$(grep -iE "(page size|pagesize)" <<<"$info" | awk '{print $NF}' | tr -d ':')
            if [[ -z "$pagesize" ]]; then
                # Alternative method for different abootimg output formats
                pagesize=$(grep -iE "page" <<<"$info" | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) print $i}' | head -1)
            fi
            base=$(grep -oE 'Base addr: +0x[0-9a-fA-F]+' <<<"$info" | awk '{print $3}')
            cmdline=$(grep -oE 'Command line: .*' <<<"$info" | sed 's/Command line: //')
            board=$(grep -oE 'Board name: .*' <<<"$info" | sed 's/Board name: //')
            [[ -n "$pagesize" ]] && eval ${out_var_prefix}_PAGESIZE="$pagesize"
            [[ -n "$base" ]] && eval ${out_var_prefix}_BASE="$base"
            [[ -n "$cmdline" ]] && eval ${out_var_prefix}_CMDLINE="\"$cmdline\""
            [[ -n "$board" ]] && eval ${out_var_prefix}_BOARD="\"$board\""
        fi
    elif command -v magiskboot >/dev/null 2>&1; then
        magiskboot unpack "$img" >/dev/null 2>&1 || true
        # magiskboot prints info to stdout; we could parse if needed (skipped for brevity)
    fi
}

bootimg_generate_mkbootimg_args() {
    # Usage: bootimg_generate_mkbootimg_args <stock_boot.img>
    local img="$1"
    local prefix="HDRTMP$$"
    bootimg_extract_header "$img" "$prefix" || return 1
    local args=()
    # Always include pagesize if found else use PAGE_SIZE env
    local ps
    eval ps="\${${prefix}_PAGESIZE}"
    if [[ -n "$ps" ]]; then args+=(--pagesize "$ps"); else args+=(--pagesize "${PAGE_SIZE:-$BOOT_IMAGE_PAGE_SIZE}"); fi
    local base; eval base="\${${prefix}_BASE}"; if [[ -n "$base" ]]; then args+=(--base "$base"); fi
    local board; eval board="\${${prefix}_BOARD}"; if [[ -n "$board" ]]; then args+=(--board "$board"); fi
    # We let caller decide cmdline; do not override if user specified
    printf '%q ' "${args[@]}"
}

# Function to verify and fix boot image page size
fix_boot_image_page_size() {
    local input_image="$1"
    local output_image="${2:-${input_image%.img}-fixed.img}"
    
    log_info "Verifying boot image page size for: $input_image"
    
    # Check if input file exists
    if [[ ! -f "$input_image" ]]; then
        log_error "Input boot image not found: $input_image"
        return 1
    fi
    
    # Use abootimg to check page size
    if command -v abootimg >/dev/null 2>&1; then
        # Try multiple patterns for page size detection
        local current_page_size=$(abootimg -i "$input_image" 2>/dev/null | grep -iE "(page size|pagesize)" | awk '{print $NF}' | tr -d ':')
        if [[ -z "$current_page_size" ]]; then
            # Alternative extraction method if abootimg format differs
            current_page_size=$(abootimg -i "$input_image" 2>/dev/null | grep -iE "page" | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) print $i}' | head -1)
        fi
        log_info "Current boot image page size: ${current_page_size:-unknown}"
        
        if [[ "$current_page_size" != "$BOOT_IMAGE_PAGE_SIZE" ]] || [[ -z "$current_page_size" ]]; then
            log_warn "Boot image has incorrect page size: ${current_page_size:-unknown} (should be $BOOT_IMAGE_PAGE_SIZE)"
            
            # Extract components
            local tmp_dir=$(mktemp -d)
            log_info "Extracting boot image components to $tmp_dir"
            
            if abootimg -x "$input_image" "$tmp_dir/bootimg.cfg" "$tmp_dir/zImage" "$tmp_dir/initrd.img" 2>/dev/null; then
                # Modify config to use correct page size
                sed -i "s/pagesize .*/pagesize = 0x$(printf '%x' $BOOT_IMAGE_PAGE_SIZE)/" "$tmp_dir/bootimg.cfg"
                
                # Rebuild the boot image
                log_info "Rebuilding boot image with correct page size"
                abootimg --create "$output_image" -f "$tmp_dir/bootimg.cfg" -k "$tmp_dir/zImage" -r "$tmp_dir/initrd.img" || {
                    log_error "Failed to create new boot image"
                    rm -rf "$tmp_dir"
                    return 1
                }
                
                # Clean up
                rm -rf "$tmp_dir"
                log_success "Boot image rebuilt with correct page size: $output_image"
                return 0
            else
                rm -rf "$tmp_dir"
                log_warn "Failed to extract with abootimg, trying alternative method"
            fi
        else
            log_success "Boot image already has correct page size"
            if [[ "$input_image" != "$output_image" && "$output_image" != "${input_image%.img}-fixed.img" ]]; then
                cp "$input_image" "$output_image"
            fi
            return 0
        fi
    fi
    
    # Alternative using Android boot tools
    if command -v mkbootimg >/dev/null 2>&1 && command -v unpackbootimg >/dev/null 2>&1; then
        local tmp_dir=$(mktemp -d)
        log_info "Using Android boot tools to fix boot image"
        
        # Unpack the boot image
        cd "$tmp_dir"
        unpackbootimg -i "$input_image" -o . || {
            log_error "Failed to unpack boot image"
            rm -rf "$tmp_dir"
            return 1
        }
        
        # Get the components
        local kernel_file=$(find . -name "*-kernel" | head -1)
        local ramdisk_file=$(find . -name "*-ramdisk*" | head -1)
        local dtb_file=$(find . -name "*-dt" | head -1)
        
        if [[ ! -f "$kernel_file" ]]; then
            log_error "Kernel file not found after unpacking"
            rm -rf "$tmp_dir"
            return 1
        fi
        
        # Build mkbootimg command
        local mkbootimg_cmd="mkbootimg --kernel $kernel_file"
        [[ -f "$ramdisk_file" ]] && mkbootimg_cmd="$mkbootimg_cmd --ramdisk $ramdisk_file"
        [[ -f "$dtb_file" ]] && mkbootimg_cmd="$mkbootimg_cmd --dt $dtb_file"
        mkbootimg_cmd="$mkbootimg_cmd --pagesize $BOOT_IMAGE_PAGE_SIZE --output $output_image"
        
        # Rebuild with correct page size
        eval $mkbootimg_cmd || {
            log_error "Failed to create new boot image with mkbootimg"
            rm -rf "$tmp_dir"
            return 1
        }
        
        # Clean up
        rm -rf "$tmp_dir"
        log_success "Boot image rebuilt with correct page size: $output_image"
        return 0
    fi
    
    # Fallback: create new boot image from scratch if possible
    if [[ -f "$BUILD_DIR/kernel/arch/arm64/boot/Image" ]]; then
        log_info "Creating new boot image from kernel and ramdisk"
        create_boot_image_from_components "$BUILD_DIR/kernel/arch/arm64/boot/Image" "" "$output_image"
        return $?
    fi
    
    log_error "No suitable tools found to fix boot image. Please install:"
    log_error "  apt-get install -y abootimg android-tools-mkbootimg"
    return 1
}

# Function to create boot image from components
create_boot_image_from_components() {
    local kernel_file="$1"
    local ramdisk_file="$2"
    local output_image="$3"
    local dtb_file="$4"
    
    log_info "Creating boot image from components..."
    
    # Check if kernel exists
    if [[ ! -f "$kernel_file" ]]; then
        log_error "Kernel file not found: $kernel_file"
        return 1
    fi
    
    # Create empty ramdisk if not provided
    if [[ -z "$ramdisk_file" || ! -f "$ramdisk_file" ]]; then
        local tmp_ramdisk=$(mktemp)
        echo | cpio -o -H newc | gzip > "$tmp_ramdisk"
        ramdisk_file="$tmp_ramdisk"
        log_info "Created empty ramdisk: $ramdisk_file"
    fi
    
    # Try mkbootimg first
    if command -v mkbootimg >/dev/null 2>&1; then
        local mkbootimg_cmd="mkbootimg --kernel $kernel_file --ramdisk $ramdisk_file --pagesize $BOOT_IMAGE_PAGE_SIZE"
        mkbootimg_cmd="$mkbootimg_cmd --base 0x40000000 --kernel_offset 0x00080000 --ramdisk_offset 0x04000000"
        mkbootimg_cmd="$mkbootimg_cmd --tags_offset 0x0e000000 --cmdline 'console=ttyS0,115200 console=tty0 rw rootwait'"
        [[ -f "$dtb_file" ]] && mkbootimg_cmd="$mkbootimg_cmd --dt $dtb_file"
        mkbootimg_cmd="$mkbootimg_cmd --output $output_image"
        
        eval $mkbootimg_cmd || {
            log_error "Failed to create boot image with mkbootimg"
            [[ "$ramdisk_file" == /tmp/* ]] && rm -f "$ramdisk_file"
            return 1
        }
        
        log_success "Boot image created with mkbootimg: $output_image"
        [[ "$ramdisk_file" == /tmp/* ]] && rm -f "$ramdisk_file"
        return 0
    fi
    
    # Try abootimg
    if command -v abootimg >/dev/null 2>&1; then
        local config_file=$(mktemp)
        cat > "$config_file" << EOF
bootsize = 0x2000000
pagesize = 0x$(printf '%x' $BOOT_IMAGE_PAGE_SIZE)
kerneladdr = 0x40080000
ramdiskaddr = 0x44000000
secondaddr = 0x40f00000
tagsaddr = 0x4e000000
name = RG35XX_H Custom
cmdline = console=ttyS0,115200 console=tty0 rw rootwait
EOF
        
        abootimg --create "$output_image" -f "$config_file" -k "$kernel_file" -r "$ramdisk_file" || {
            log_error "Failed to create boot image with abootimg"
            rm -f "$config_file"
            [[ "$ramdisk_file" == /tmp/* ]] && rm -f "$ramdisk_file"
            return 1
        }
        
        rm -f "$config_file"
        log_success "Boot image created with abootimg: $output_image"
        [[ "$ramdisk_file" == /tmp/* ]] && rm -f "$ramdisk_file"
        return 0
    fi
    
    log_error "No boot image creation tools found"
    [[ "$ramdisk_file" == /tmp/* ]] && rm -f "$ramdisk_file"
    return 1
}

# Function to get boot image info
get_boot_image_info() {
    local boot_image="$1"
    
    if [[ ! -f "$boot_image" ]]; then
        echo "Boot image not found: $boot_image"
        return 1
    fi
    
    echo "Boot image: $boot_image"
    echo "Size: $(stat -c %s "$boot_image") bytes"
    
    if command -v abootimg >/dev/null 2>&1; then
        echo "=== abootimg info ==="
        abootimg -i "$boot_image" 2>/dev/null || echo "Failed to read with abootimg"
    fi
    
    if command -v file >/dev/null 2>&1; then
        echo "=== file info ==="
        file "$boot_image"
    fi
    
    return 0
}

# Function to install required tools
install_boot_tools() {
    log_info "Installing boot image tools..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y abootimg android-tools-mkbootimg android-tools-fsutils || {
            log_error "Failed to install boot image tools"
            return 1
        }
        log_success "Boot image tools installed successfully"
        return 0
    elif command -v yum >/dev/null 2>&1; then
        yum install -y abootimg android-tools || {
            log_error "Failed to install boot image tools"
            return 1
        }
        log_success "Boot image tools installed successfully"
        return 0
    else
        log_error "Package manager not found. Please install abootimg and android-tools manually"
        return 1
    fi
}

bootimg_full_hash() {
    local img="$1"
    [[ -f "$img" ]] || { echo "bootimg_full_hash: no file"; return 1; }
    sha256sum "$img" | awk '{print $1}'
}

# Function to verify boot image page size
verify_boot_image_page_size() {
    local boot_image="$1"
    local expected_size="${2:-$BOOT_IMAGE_PAGE_SIZE}"
    
    if [[ ! -f "$boot_image" ]]; then
        log_error "Boot image not found: $boot_image"
        return 1
    fi
    
    local current_size=""
    if command -v abootimg >/dev/null 2>&1; then
        current_size=$(abootimg -i "$boot_image" 2>/dev/null | grep -iE "(page size|pagesize)" | awk '{print $NF}' | tr -d ':')
        if [[ -z "$current_size" ]]; then
            # Alternative extraction method
            current_size=$(abootimg -i "$boot_image" 2>/dev/null | grep -iE "page" | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) print $i}' | head -1)
        fi
    fi
    
    if [[ "$current_size" == "$expected_size" ]]; then
        log_success "Boot image has correct page size: $current_size"
        return 0
    else
        log_warn "Boot image page size mismatch: $current_size (expected: $expected_size)"
        return 1
    fi
}
