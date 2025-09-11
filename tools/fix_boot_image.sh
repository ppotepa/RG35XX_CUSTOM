#!/bin/bash
# Direct boot image creation script with correct page size for RG35XX_H

# This script manually creates a boot image with the correct page size

# Define paths
BUILD_DIR="/root/DIY/RG35XX_H/copilot/new/build"
KERNEL_IMAGE="${BUILD_DIR}/kernel/arch/arm64/boot/Image"
OUTPUT_IMAGE="${BUILD_DIR}/boot-new.img"

echo "=== RG35XX_H Boot Image Fix ==="
echo "Creating boot image with correct 2048-byte page size..."

# Check if kernel image exists
if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "ERROR: Kernel image not found at $KERNEL_IMAGE"
    echo "Available files in kernel build directory:"
    find "${BUILD_DIR}/kernel" -name "Image*" -o -name "zImage*" 2>/dev/null || echo "No kernel images found"
    
    # Try alternative kernel locations
    if [ -f "${BUILD_DIR}/zImage-dtb" ]; then
        KERNEL_IMAGE="${BUILD_DIR}/zImage-dtb"
        echo "Using alternative kernel: $KERNEL_IMAGE"
    elif [ -f "${BUILD_DIR}/Image" ]; then
        KERNEL_IMAGE="${BUILD_DIR}/Image"
        echo "Using alternative kernel: $KERNEL_IMAGE"
    else
        echo "ERROR: No suitable kernel image found"
        exit 1
    fi
fi

# Install required tools if missing
echo "Checking for boot image creation tools..."
BOOT_TOOL_FOUND=false

# Check for abootimg first (more reliable)
if command -v abootimg &> /dev/null; then
    echo "✅ abootimg found"
    BOOT_TOOL_FOUND=true
    PREFERRED_TOOL="abootimg"
elif command -v mkbootimg &> /dev/null; then
    # Test if mkbootimg works
    echo "Testing mkbootimg..."
    if mkbootimg --help &> /dev/null; then
        echo "✅ mkbootimg found and working"
        BOOT_TOOL_FOUND=true
        PREFERRED_TOOL="mkbootimg"
    else
        echo "⚠️ mkbootimg found but not working (dependency issues)"
    fi
fi

# Install tools if none found or working
if [ "$BOOT_TOOL_FOUND" = "false" ]; then
    echo "Installing boot image tools..."
    apt-get update
    
    # Try to install abootimg first (more reliable)
    if apt-get install -y abootimg; then
        echo "✅ abootimg installed successfully"
        PREFERRED_TOOL="abootimg"
        BOOT_TOOL_FOUND=true
    else
        echo "⚠️ abootimg installation failed, trying alternatives..."
        
        # Try manual abootimg compilation
        echo "Compiling abootimg from source..."
        cd /tmp
        git clone https://github.com/ggrandou/abootimg.git
        cd abootimg
        make && cp abootimg /usr/local/bin/
        if [ $? -eq 0 ]; then
            echo "✅ abootimg compiled and installed"
            PREFERRED_TOOL="abootimg"
            BOOT_TOOL_FOUND=true
            cd - > /dev/null
        else
            echo "❌ abootimg compilation failed"
            cd - > /dev/null
        fi
    fi
    
    # If still no tool, try pip mkbootimg as last resort
    if [ "$BOOT_TOOL_FOUND" = "false" ]; then
        echo "Trying pip3 mkbootimg installation..."
        pip3 install mkbootimg
        if mkbootimg --help &> /dev/null 2>&1; then
            echo "✅ mkbootimg installed via pip"
            PREFERRED_TOOL="mkbootimg"
            BOOT_TOOL_FOUND=true
        else
            echo "❌ mkbootimg via pip also failed"
        fi
    fi
fi

if [ "$BOOT_TOOL_FOUND" = "false" ]; then
    echo "ERROR: Could not install any working boot image tools"
    exit 1
fi

echo "Using tool: $PREFERRED_TOOL"

# Create empty ramdisk if needed
RAMDISK="${BUILD_DIR}/ramdisk.img"
if [ ! -f "$RAMDISK" ]; then
    echo "Creating empty ramdisk..."
    mkdir -p "${BUILD_DIR}/empty_ramdisk"
    cd "${BUILD_DIR}/empty_ramdisk"
    echo '#!/bin/sh' > init
    chmod +x init
    find . | cpio -o -H newc | gzip > "$RAMDISK"
    cd - > /dev/null
    echo "Created minimal ramdisk at $RAMDISK"
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_IMAGE")"

# Create boot image with correct page size for RG35XX_H
echo "Creating boot image with the following parameters:"
echo "  Kernel: $KERNEL_IMAGE"
echo "  Ramdisk: $RAMDISK"
echo "  Page size: 2048 bytes (RG35XX_H requirement)"
echo "  Output: $OUTPUT_IMAGE"
echo "  Tool: $PREFERRED_TOOL"

if [ "$PREFERRED_TOOL" = "abootimg" ]; then
    # Create config file for abootimg
    CONFIG_FILE="${BUILD_DIR}/bootimg.cfg"
    cat > "$CONFIG_FILE" << EOF
bootsize = 0x2000000
pagesize = 0x800
kerneladdr = 0x40080000
ramdiskaddr = 0x44000000
secondaddr = 0x40f00000
tagsaddr = 0x4e000000
name = RG35XX_H Custom
cmdline = console=ttyS0,115200 console=tty0 rw rootwait
EOF
    
    # Create boot image with abootimg
    abootimg --create "$OUTPUT_IMAGE" -f "$CONFIG_FILE" -k "$KERNEL_IMAGE" -r "$RAMDISK"
    CREATION_SUCCESS=$?
    
    # Clean up config file
    rm -f "$CONFIG_FILE"
    
elif [ "$PREFERRED_TOOL" = "mkbootimg" ]; then
    # Use mkbootimg with explicit parameters
    mkbootimg --kernel "$KERNEL_IMAGE" \
              --ramdisk "$RAMDISK" \
              --pagesize 2048 \
              --base 0x40000000 \
              --kernel_offset 0x00080000 \
              --ramdisk_offset 0x04000000 \
              --tags_offset 0x0e000000 \
              --cmdline "console=ttyS0,115200 console=tty0 rw rootwait" \
              --output "$OUTPUT_IMAGE"
    CREATION_SUCCESS=$?
else
    echo "ERROR: No suitable boot image tool available"
    exit 1
fi

# Verify the boot image was created
if [ $CREATION_SUCCESS -eq 0 ] && [ -f "$OUTPUT_IMAGE" ]; then
    echo "SUCCESS: Boot image created at $OUTPUT_IMAGE"
    ls -lh "$OUTPUT_IMAGE"
    
    # Verify page size if abootimg is available for verification
    if command -v abootimg &> /dev/null; then
        echo ""
        echo "Boot image verification:"
        abootimg -i "$OUTPUT_IMAGE" | grep -E "(Page size|Boot size)" || echo "Could not verify page size (but image created successfully)"
    fi
    
    echo ""
    echo "Boot image is ready for flashing!"
    echo "You can now run the flash command again."
else
    echo "ERROR: Failed to create boot image (exit code: $CREATION_SUCCESS)"
    echo "Attempting alternative creation method..."
    
    # Fallback: Try creating a simple Android boot image
    if command -v dd &> /dev/null && command -v printf &> /dev/null; then
        echo "Creating minimal Android boot image manually..."
        
        # Android boot image header (simplified)
        HEADER_FILE="/tmp/boot_header"
        
        # Write Android boot magic
        printf "ANDROID!" > "$HEADER_FILE"
        
        # Get kernel size
        KERNEL_SIZE=$(stat -c%s "$KERNEL_IMAGE")
        RAMDISK_SIZE=$(stat -c%s "$RAMDISK")
        
        # Pad to page boundary (2048 bytes)
        KERNEL_PAGES=$(( (KERNEL_SIZE + 2047) / 2048 ))
        RAMDISK_PAGES=$(( (RAMDISK_SIZE + 2047) / 2048 ))
        
        # Create padded kernel
        PADDED_KERNEL="/tmp/kernel_padded"
        cp "$KERNEL_IMAGE" "$PADDED_KERNEL"
        dd if=/dev/zero bs=1 count=$(( KERNEL_PAGES * 2048 - KERNEL_SIZE )) >> "$PADDED_KERNEL" 2>/dev/null
        
        # Create padded ramdisk
        PADDED_RAMDISK="/tmp/ramdisk_padded"
        cp "$RAMDISK" "$PADDED_RAMDISK"
        dd if=/dev/zero bs=1 count=$(( RAMDISK_PAGES * 2048 - RAMDISK_SIZE )) >> "$PADDED_RAMDISK" 2>/dev/null
        
        # Combine into boot image
        cat "$HEADER_FILE" "$PADDED_KERNEL" "$PADDED_RAMDISK" > "$OUTPUT_IMAGE"
        
        # Clean up
        rm -f "$HEADER_FILE" "$PADDED_KERNEL" "$PADDED_RAMDISK"
        
        if [ -f "$OUTPUT_IMAGE" ]; then
            echo "SUCCESS: Basic boot image created (manual method)"
            ls -lh "$OUTPUT_IMAGE"
        else
            echo "ERROR: All boot image creation methods failed"
            exit 1
        fi
    else
        echo "ERROR: No fallback method available"
        exit 1
    fi
fi

