#!/usr/bin/env bash
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

echo "[*] Checking tools..."
need git; need "${CROSS_COMPILE}gcc"; need make; need lsblk; need sgdisk; need parted; need dd
HAVE_MKBOOTIMG=0; command -v mkbootimg >/dev/null 2>&1 && HAVE_MKBOOTIMG=1
HAVE_ABOOTIMG=0;  command -v abootimg  >/dev/null 2>&1 && HAVE_ABOOTIMG=1
HAVE_UNMK=0;      command -v unmkbootimg >/dev/null 2>&1 && HAVE_UNMK=1
HAVE_MAGISK=0;    command -v magiskboot  >/dev/null 2>&1 && HAVE_MAGISK=1
(( HAVE_MKBOOTIMG + HAVE_ABOOTIMG + HAVE_UNMK + HAVE_MAGISK > 0 )) || { echo "Need at least one of: mkbootimg / abootimg / unmkbootimg / magiskboot" >&2; exit 2; }

echo "[*] Verifying device nodes..."
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT "$EMMC_DEV"

echo "[*] Checking config_patch in current dir..."
PATCH="$PWD/config_patch"
if [[ -d "$PATCH" ]]; then
  mapfile -t CFGS < <(find "$PATCH" -maxdepth 1 -name '*.config' -print | sort)
  [[ ${#CFGS[@]} -gt 0 ]] || { echo "No *.config files in ./config_patch/" >&2; exit 2; }
elif [[ -f "$PATCH" ]]; then
  CFGS=("$PATCH")
else
  echo "ERROR: expected ./config_patch (file) or ./config_patch/*.config (dir) in CWD" >&2
  exit 2
fi

### --- backups (GPT + p4 + p5) ---
echo "[*] Backing up GPT and key partitions..."
mkdir -p backups
sgdisk --backup=backups/gpt-backup.bin "$EMMC_DEV"
sudo dd if="$BOOT_PART" of=backups/boot-p4-backup.img bs=4M conv=fsync status=progress
sudo dd if="$ROOT_PART" of=backups/rootfs-p5-backup.img bs=4M conv=fsync status=progress
( cd backups && sha256sum * > backups.sha256 )

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
echo "[*] Extracting ramdisk from stock boot..."
cd "$OLDPWD"
BOOT_STOCK="backups/boot-p4-backup.img"
RAMDISK="ramdisk.cpio.gz"

TMPDIR=$(mktemp -d)
pushd "$TMPDIR" >/dev/null
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
popd >/dev/null
rm -rf "$TMPDIR"
[[ -f "$RAMDISK" ]] || { echo "Could not extract ramdisk from p4; aborting." >&2; exit 2; }

### --- package boot image ---
echo "[*] Packaging boot image ($PACK_MODE)..."
IMG_OUT="boot-new.img"
KIMG="$O/arch/arm64/boot/Image"

if [[ "$PACK_MODE" == "catdt" ]]; then
  cat "$KIMG" "$DTB" > Image+dtb
  if (( HAVE_MKBOOTIMG )); then
    mkbootimg --kernel Image+dtb --ramdisk "$RAMDISK" --pagesize "$PAGE_SIZE" \
      --cmdline "$KCMD" -o "$IMG_OUT"
  else
    echo "mkbootimg not available; for abootimg, use a cfg from stock. Skipping auto-pack."
    exit 2
  fi
elif [[ "$PACK_MODE" == "with-dt" ]]; then
  cat "$DTB" > dtb.img
  if (( HAVE_MKBOOTIMG )); then
    mkbootimg --kernel "$KIMG" --dt dtb.img --ramdisk "$RAMDISK" --pagesize "$PAGE_SIZE" \
      --cmdline "$KCMD" -o "$IMG_OUT"
  else
    echo "mkbootimg not available; for abootimg, use a cfg from stock. Skipping auto-pack."
    exit 2
  fi
else
  echo "Unknown PACK_MODE: $PACK_MODE" >&2; exit 2;
fi

### --- install modules to p5 ---
echo "[*] Installing kernel modules to $ROOT_PART..."
sudo mkdir -p /mnt/p5
sudo mount "$ROOT_PART" /mnt/p5 || true
( cd linux && make ${O:+O=$O} modules_install INSTALL_MOD_PATH=/mnt/p5 )
sync
sudo umount /mnt/p5 || true

### --- flash p4 (confirmation) ---
echo
echo "About to flash $IMG_OUT -> $BOOT_PART (pagesize=$PAGE_SIZE)."
read -r -p "Type 'I UNDERSTAND' to proceed: " ACK
[[ "$ACK" == "I UNDERSTAND" ]] || { echo "Aborted."; exit 1; }

sudo dd if="$IMG_OUT" of="$BOOT_PART" bs=4M conv=fsync status=progress
sync
echo "[*] Done. Power-cycle the device."
echo "[*] If it loops after splash: try a different DTB_NAME or PACK_MODE, verify --pagesize=$PAGE_SIZE."
