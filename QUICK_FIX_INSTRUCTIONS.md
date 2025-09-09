# Quick Boot Image Fix Instructions

## Problem
The flashing process fails with:
- "Boot image has incorrect page size: (should be 2048)"
- "/root/DIY/RG35XX_H/copilot/new/build/boot-new.img: No such file or directory"

## Quick Solution

Run the boot image fix script directly:

```bash
cd /root/DIY/RG35XX_H/copilot/new
./fix_boot_image.sh
```

This script will:
1. Find your existing kernel image
2. Create a proper boot image with 2048-byte page size
3. Place it in the correct location for flashing

## Then Resume Flashing

After running the fix script, you can resume the flashing process:

```bash
sudo ./run_ubuntu.sh --skip-build
```

The flashing should now succeed since the boot image will be available with the correct page size.

## What the Fix Script Does

- Locates your built kernel image
- Creates an empty ramdisk if needed
- Uses mkbootimg with the correct RG35XX_H parameters:
  - Page size: 2048 bytes
  - Base address: 0x40000000
  - Kernel offset: 0x00080000
  - Ramdisk offset: 0x04000000
  - Tags offset: 0x0e000000
  - Command line: "console=ttyS0,115200 console=tty0 rw rootwait"

## No Full Rebuild Required!

This fix uses your existing kernel build and just creates the missing boot image file with the correct parameters. You don't need to rebuild everything from scratch.
