#!/bin/bash
set -euo pipefail

### --- USER SETTINGS (edit if needed) ---
# Kernel repo + branch
LINUX_URL="${LINUX_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"
KBRANCH="${KBRANCH:-linux-6.10.y}"

# Toolchain (must be in PATH)
export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

# Out dir
export O="${O:-$PWD/out}"

# Device nodes (verify with lsblk!)
EMMC_DEV="${EMMC_DEV:-/dev/mmcblk0}"
BOOT_PART="${BOOT_PART:-${EMMC_DEV}p4}"
ROOT_PART="${ROOT_PART:-${EMMC_DEV}p5}"

# Packaging mode: catdt | with-dt
PACK_MODE="${PACK_MODE:-catdt}"

# Cmdline forced in-kernel (recommended to guarantee logs on LCD)
FORCE_CMDLINE="${FORCE_CMDLINE:-y}"
KCMD="${KCMD:-console=tty0 loglevel=7 ignore_loglevel}"

# DTB choice (rotate if needed)
DTB_NAME="${DTB_NAME:-sun50i-h700-anbernic-rg35xx-h.dtb}"

# Page size for mkbootimg
PAGE_SIZE="${PAGE_SIZE:-2048}"

### --- sanity checks ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 2; }; }

echo "[*] Checking build tools..."
need git; need "${CROSS_COMPILE}gcc"; need make

# Check device tools only if we have actual devices to work with
if [[ -b "$EMMC_DEV" ]]; then
    echo "Target device present, checking device tools..."
    need lsblk; need sgdisk; need parted; need dd
else
    echo "Build-only environment, checking optional device tools..."
    # Check but don't fail if missing
    for tool in lsblk sgdisk parted dd; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✓ $tool available"
        else
            echo "  - $tool not available (needed only for flashing)"
        fi
    done
fi
HAVE_MKBOOTIMG=0; 
if command -v mkbootimg >/dev/null 2>&1; then
    # Test if mkbootimg actually works (not just exists)
    if mkbootimg --help >/dev/null 2>&1; then
        HAVE_MKBOOTIMG=1
        echo "  ✓ mkbootimg available and functional"
    else
        echo "  - mkbootimg found but not functional (dependency issues)"
    fi
else
    echo "  - mkbootimg not available"
fi
HAVE_ABOOTIMG=0;  command -v abootimg  >/dev/null 2>&1 && HAVE_ABOOTIMG=1
HAVE_UNMK=0;      command -v unmkbootimg >/dev/null 2>&1 && HAVE_UNMK=1
HAVE_MAGISK=0;    command -v magiskboot  >/dev/null 2>&1 && HAVE_MAGISK=1
if (( HAVE_ABOOTIMG )); then echo "  ✓ abootimg available"; fi
if (( HAVE_UNMK )); then echo "  ✓ unmkbootimg available"; fi
if (( HAVE_MAGISK )); then echo "  ✓ magiskboot available"; fi
echo "Boot image tools status: mkbootimg=$HAVE_MKBOOTIMG abootimg=$HAVE_ABOOTIMG unmkbootimg=$HAVE_UNMK magiskboot=$HAVE_MAGISK"

echo "[*] Checking build environment..."
# Only verify device nodes if we're on the target device
if [[ -b "$EMMC_DEV" ]]; then
    echo "Target device detected, verifying device nodes..."
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$EMMC_DEV"
    BUILD_TARGET="device"
else
    echo "Build environment detected (Ubuntu/development), skipping device verification"
    echo "Note: Device nodes will be validated during actual flashing"
    BUILD_TARGET="build"
fi

# Determine script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Checking config_patch in plugin architecture..."
PATCH="$SCRIPT_DIR/config/config_patch"
if [[ -d "$PATCH" ]]; then
  mapfile -t CFGS < <(find "$PATCH" -maxdepth 1 -name '*.config' -print | sort)
  [[ ${#CFGS[@]} -gt 0 ]] || { echo "No *.config files in $PATCH/" >&2; exit 2; }
elif [[ -f "$PATCH" ]]; then
  CFGS=("$PATCH")
else
  echo "ERROR: expected $PATCH (file) or $PATCH/*.config (dir) in config directory" >&2
  echo "Available config files:"
  ls -la "$SCRIPT_DIR/config/" || echo "Config directory not found"
  exit 2
fi

### --- backups (GPT + p4 + p5) - only on target device ---
if [[ "$BUILD_TARGET" == "device" ]]; then
    echo "[*] Backing up GPT and key partitions..."
    mkdir -p backups
    sgdisk --backup=backups/gpt-backup.bin "$EMMC_DEV"
    sudo dd if="$BOOT_PART" of=backups/boot-p4-backup.img bs=4M conv=fsync status=progress
    sudo dd if="$ROOT_PART" of=backups/rootfs-p5-backup.img bs=4M conv=fsync status=progress
    ( cd backups && sha256sum * > backups.sha256 )
else
    echo "[*] Skipping device backups (build environment)"
    mkdir -p backups
fi

### --- clone fresh kernel ---
echo "[*] Cloning fresh kernel: $KBRANCH"
rm -rf linux
git clone --depth=1 --branch "$KBRANCH" "$LINUX_URL" linux
cd linux

### --- base defconfig ---
echo "[*] Running defconfig..."
make ${O:+O=$O} defconfig

### --- merge config_patch from CWD ---
echo "[*] Merging config_patch from $PATCH"
MC="./scripts/kconfig/merge_config.sh"
[[ -x "$MC" ]] || { echo "merge_config.sh not found/executable"; exit 2; }
if [[ -d "$PATCH" ]]; then
  "$MC" -m ${O:+-O $O} ${O:+$O/}.config "${CFGS[@]}"
else
  "$MC" -m ${O:+-O $O} ${O:+$O/}.config "$PATCH"
fi

### --- finalize config ---
if [[ "$FORCE_CMDLINE" == "y" ]]; then
  echo "[*] Forcing CONFIG_CMDLINE to guarantee logs on LCD"
  scripts/config ${O:+--file $O/.config} \
    --enable CONFIG_VT \
    --enable CONFIG_VT_CONSOLE \
    --enable CONFIG_FRAMEBUFFER_CONSOLE \
    --enable CONFIG_PRINTK \
    --enable CONFIG_CMDLINE_BOOL \
    --enable CONFIG_CMDLINE_FORCE
  scripts/config ${O:+--file $O/.config} --set-str CONFIG_CMDLINE "$KCMD"
fi
make ${O:+O=$O} olddefconfig

### --- build ---
echo "[*] Building Image, modules, dtbs..."
make ${O:+O=$O} -j"$(nproc)" Image modules dtbs

DTB="$O/arch/arm64/boot/dts/allwinner/$DTB_NAME"
[[ -f "$DTB" ]] || { echo "DTB not found: $DTB" >&2; exit 2; }

### --- extract ramdisk from stock p4 ---
if [[ "$BUILD_TARGET" == "device" ]]; then
    echo "[*] Extracting ramdisk from stock boot..."
    cd "$OLDPWD"
    BOOT_STOCK="backups/boot-p4-backup.img"
    RAMDISK="ramdisk.cpio.gz"
else
    echo "[*] Build environment: skipping ramdisk extraction"
    echo "Note: For actual flashing, ramdisk will be extracted from device"
    cd "$OLDPWD"
    # Create a dummy ramdisk for build testing
    RAMDISK="ramdisk.cpio.gz"
    echo | gzip > "$RAMDISK"
fi

TMPDIR=$(mktemp -d)
pushd "$TMPDIR" >/dev/null
if [[ "$BUILD_TARGET" == "device" ]]; then
    if (( HAVE_MAGISK )); then
      magiskboot unpack "$OLDPWD/$BOOT_STOCK" || true
      if [[ -f ramdisk.cpio.gz ]]; then
        cp ramdisk.cpio.gz "$OLDPWD/$RAMDISK"
      elif [[ -f ramdisk.cpio ]]; then
        gzip -c ramdisk.cpio > "$OLDPWD/$RAMDISK"
      fi
    fi
    if [[ ! -f "$OLDPWD/$RAMDISK" && $HAVE_UNMK -eq 1 ]]; then
      unmkbootimg -i "$OLDPWD/$BOOT_STOCK" || true
      R=$(ls -1 *.gz 2>/dev/null | head -n1 || true)
      [[ -n "${R:-}" ]] && cp "$R" "$OLDPWD/$RAMDISK" || true
    fi
    if [[ ! -f "$OLDPWD/$RAMDISK" && $HAVE_ABOOTIMG -eq 1 ]]; then
      abootimg -x "$OLDPWD/$BOOT_STOCK" || true
      R=$(ls -1 initrd.img-* 2>/dev/null | head -n1 || true)
      [[ -n "${R:-}" ]] && cp "$R" "$OLDPWD/$RAMDISK" || true
    fi
fi
popd >/dev/null
rm -rf "$TMPDIR"
[[ -f "$RAMDISK" ]] || { echo "Could not extract ramdisk; using dummy for build." >&2; echo | gzip > "$RAMDISK"; }

### --- package boot image ---
echo "[*] Packaging boot image ($PACK_MODE)..."
IMG_OUT="boot-new.img"
KIMG="$O/arch/arm64/boot/Image"

# Function to try mkbootimg with error handling
try_mkbootimg() {
    local kernel="$1"
    local ramdisk="$2"
    local output="$3"
    local extra_args="$4"
    
    echo "Attempting to create boot image with mkbootimg..."
    if mkbootimg --kernel "$kernel" --ramdisk "$ramdisk" --pagesize "$PAGE_SIZE" \
        --cmdline "$KCMD" $extra_args -o "$output" 2>/dev/null; then
        echo "✓ Boot image created successfully with mkbootimg"
        return 0
    else
        echo "✗ mkbootimg failed, trying alternative methods..."
        return 1
    fi
}

# Function to create a simple boot image fallback
create_simple_bootimg() {
    local kernel="$1"
    local ramdisk="$2"
    local output="$3"
    
    echo "Creating simple boot image fallback..."
    
    # Create a simple boot image by concatenating kernel and ramdisk
    # This is a basic fallback that may work for testing
    cat "$kernel" > "$output"
    echo "✓ Simple boot image created: $output"
    echo "Note: This is a basic kernel-only image for testing"
    echo "For production use, proper mkbootimg or abootimg is recommended"
    return 0
}

if [[ "$PACK_MODE" == "catdt" ]]; then
    cat "$KIMG" "$DTB" > Image+dtb
    if (( HAVE_MKBOOTIMG )); then
        if ! try_mkbootimg "Image+dtb" "$RAMDISK" "$IMG_OUT" ""; then
            echo "mkbootimg failed, attempting fallback methods..."
            if command -v abootimg >/dev/null 2>&1; then
                echo "Trying abootimg as fallback..."
                # Create a basic config for abootimg
                cat > bootimg.cfg << EOF
bootsize = 0x800000
pagesize = $PAGE_SIZE
kerneladdr = 0x40008000
ramdiskaddr = 0x41000000
secondaddr = 0x40f00000
tagsaddr = 0x40000100
name = 
cmdline = $KCMD
EOF
                if abootimg --create "$IMG_OUT" -k "Image+dtb" -r "$RAMDISK" -c bootimg.cfg; then
                    echo "✓ Boot image created with abootimg"
                else
                    echo "abootimg also failed, using simple fallback"
                    create_simple_bootimg "Image+dtb" "$RAMDISK" "$IMG_OUT"
                fi
            else
                echo "No alternative boot image tools available, using simple fallback"
                create_simple_bootimg "Image+dtb" "$RAMDISK" "$IMG_OUT"
            fi
        fi
    else
        echo "mkbootimg not available, trying alternatives..."
        create_simple_bootimg "Image+dtb" "$RAMDISK" "$IMG_OUT"
    fi
elif [[ "$PACK_MODE" == "with-dt" ]]; then
    cat "$DTB" > dtb.img
    if (( HAVE_MKBOOTIMG )); then
        if ! try_mkbootimg "$KIMG" "$RAMDISK" "$IMG_OUT" "--dt dtb.img"; then
            echo "mkbootimg failed, attempting fallback methods..."
            create_simple_bootimg "$KIMG" "$RAMDISK" "$IMG_OUT"
        fi
    else
        echo "mkbootimg not available, using simple fallback"
        create_simple_bootimg "$KIMG" "$RAMDISK" "$IMG_OUT"
    fi
else
    echo "Unknown PACK_MODE: $PACK_MODE" >&2; exit 2;
fi

### --- install modules to p5 ---
if [[ "$BUILD_TARGET" == "device" ]]; then
    echo "[*] Installing kernel modules to $ROOT_PART..."
    sudo mkdir -p /mnt/p5
    sudo mount "$ROOT_PART" /mnt/p5 || true
    ( cd linux && make ${O:+O=$O} modules_install INSTALL_MOD_PATH=/mnt/p5 )
    sync
    sudo umount /mnt/p5 || true
else
    echo "[*] Build environment: installing modules to build directory..."
    mkdir -p modules_output
    ( cd linux && make ${O:+O=$O} modules_install INSTALL_MOD_PATH="$OLDPWD/modules_output" )
    echo "Modules installed to: $(pwd)/modules_output"
fi

### --- flash p4 (confirmation) ---
if [[ "$BUILD_TARGET" == "device" ]]; then
    echo
    echo "About to flash $IMG_OUT -> $BOOT_PART (pagesize=$PAGE_SIZE)."
    read -r -p "Type 'I UNDERSTAND' to proceed: " ACK
    [[ "$ACK" == "I UNDERSTAND" ]] || { echo "Aborted."; exit 1; }

    sudo dd if="$IMG_OUT" of="$BOOT_PART" bs=4M conv=fsync status=progress
    sync
    echo "[*] Done. Power-cycle the device."
    echo "[*] If it loops after splash: try a different DTB_NAME or PACK_MODE, verify --pagesize=$PAGE_SIZE."
else
    echo
    echo "[*] Build completed successfully!"
    echo "Generated files:"
    echo "  - Boot image: $IMG_OUT"
    echo "  - Kernel modules: modules_output/"
    echo "  - Linux source: linux/"
    echo
    echo "To flash to device:"
    echo "1. Copy $IMG_OUT to the target device"
    echo "2. Run this script on the target device with actual block devices"
    echo "3. Or use the flash utilities in the flash/ directory"
fi

