#!/bin/bash
# Find and migrate existing build outputs

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/build"

echo "=== RG35HAXX Build Output Migration ==="
echo "Searching for existing build outputs..."

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check for existing kernel images
found_kernel=false
for kernel_file in "$SCRIPT_DIR"/*/zImage-dtb "$SCRIPT_DIR"/*/out/zImage-dtb "$SCRIPT_DIR"/linux/arch/arm64/boot/Image; do
    if [[ -f "$kernel_file" ]]; then
        echo "Found kernel: $kernel_file"
        if [[ ! -f "$OUTPUT_DIR/zImage-dtb" ]]; then
            if [[ "$kernel_file" == *"/Image" ]]; then
                echo "Found raw kernel Image, need to combine with DTB later"
                cp "$kernel_file" "$OUTPUT_DIR/Image"
            else
                cp "$kernel_file" "$OUTPUT_DIR/zImage-dtb"
                found_kernel=true
                echo "  → Migrated to $OUTPUT_DIR/zImage-dtb"
            fi
        fi
    fi
done

# Check for existing rootfs
found_rootfs=false
for rootfs_file in "$SCRIPT_DIR"/*/rootfs.tar.gz "$SCRIPT_DIR"/*/out/rootfs.tar.gz; do
    if [[ -f "$rootfs_file" ]]; then
        echo "Found rootfs: $rootfs_file"
        if [[ ! -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
            cp "$rootfs_file" "$OUTPUT_DIR/rootfs.tar.gz"
            found_rootfs=true
            echo "  → Migrated to $OUTPUT_DIR/rootfs.tar.gz"
        fi
    fi
done

# Check for existing rootfs directory
if [[ -d "$SCRIPT_DIR/rootfs" ]] && [[ ! -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
    echo "Found rootfs directory, creating tarball..."
    cd "$SCRIPT_DIR/rootfs"
    tar -czf "$OUTPUT_DIR/rootfs.tar.gz" .
    found_rootfs=true
    echo "  → Created $OUTPUT_DIR/rootfs.tar.gz"
fi

# Summary
echo
echo "=== Migration Summary ==="
if [[ "$found_kernel" == "true" ]]; then
    size=$(stat -c%s "$OUTPUT_DIR/zImage-dtb" | numfmt --to=iec)
    echo "✅ Kernel: $OUTPUT_DIR/zImage-dtb ($size)"
else
    echo "❌ No kernel found - will need to build"
fi

if [[ "$found_rootfs" == "true" ]]; then
    size=$(stat -c%s "$OUTPUT_DIR/rootfs.tar.gz" | numfmt --to=iec)
    echo "✅ RootFS: $OUTPUT_DIR/rootfs.tar.gz ($size)"
else
    echo "❌ No rootfs found - will need to build"
fi

echo
if [[ "$found_kernel" == "true" ]] && [[ "$found_rootfs" == "true" ]]; then
    echo "🎉 Both kernel and rootfs found! You can now use:"
    echo "   sudo ./run_ubuntu.sh --skip-build --skip-backup"
elif [[ "$found_kernel" == "true" ]] || [[ "$found_rootfs" == "true" ]]; then
    echo "⚠️  Partial build found. You may want to run:"
    echo "   sudo ./run_ubuntu.sh --force-build"
else
    echo "🔨 No existing builds found. Run full build:"
    echo "   sudo ./run_ubuntu.sh"
fi
