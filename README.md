# RG35XX_H Custom Linux Builder

A modular build system for creating custom Linux kernels for the RG35XX_H handheld gaming device with WiFi, Bluetooth, USB gadgets, and automated flashing capabilities.

## Features

- **Custom Kernel Configuration**: Apply your own kernel config patches
- **Device Tree Support**: Automatic detection and building of RG35XX_H device trees
- **Modular Architecture**: Clean separation of concerns following SOLID principles
- **Progress Tracking**: Visual progress bars for build and flash operations
- **Resume Capability**: Start builds from specific steps (kernel, busybox, rootfs, flash)
- **Automatic Flashing**: Auto-detect SD cards and flash with minimal user interaction
- **Backup Creation**: Automatic backup of original firmware (optional)

## Project Structure

```
new/                           # Main project directory
├── build_modular.sh           # Main entry point (new modular version)
├── build_rg35xx.sh           # Original monolithic script
├── config/
│   └── constants.sh          # Configuration constants
├── lib/
│   ├── logger.sh            # Logging utilities
│   ├── system.sh            # System utilities
│   └── device.sh            # Device management
├── builders/
│   ├── kernel_builder.sh    # Kernel building
│   ├── busybox_builder.sh   # BusyBox building
│   └── rootfs_builder.sh    # Root filesystem
├── flash/
│   └── flasher.sh           # SD card flashing
├── config_patch            # Kernel configuration
├── busybox_config_patch     # BusyBox configuration (optional)
├── run_ubuntu.sh           # Ubuntu execution wrapper
└── out/                     # Build outputs
```

## Quick Start

### Prerequisites
- Ubuntu / Debian (or WSL) with root access
- Toolchain: `aarch64-linux-gnu-*`
- Utilities: `git make gcc dtc mkbootimg (recommended) magiskboot|unmkbootimg|abootimg sgdisk parted pv cpio gzip` 
- Access to internal eMMC (p4 = boot, p5 = rootfs) or SD card clone

### One-Shot End-to-End Script
Use when you want a fresh, clean build & immediate flash (backs up GPT + p4 + p5). Place your kernel config as `./config_patch` (file or directory of `*.config`).

```bash
chmod +x build_rg35xxh.sh
sudo ./build_rg35xxh.sh                 # Build + backup + package + modules + flash
sudo PACK_MODE=with-dt ./build_rg35xxh.sh  # Alternate packaging
sudo DTB_NAME=sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb ./build_rg35xxh.sh
```

If boot loops after splash: re-run with a different `DTB_NAME` or `PACK_MODE=with-dt`.

### Modular Build Flow
For incremental development with caching.

```bash
sudo ./run_ubuntu.sh                 # Full build + detect & flash SD
sudo ./run_ubuntu.sh --skip-build    # Only flash existing outputs
sudo ./run_ubuntu.sh --force-build   # Force fresh rebuild
sudo ./run_ubuntu.sh --dtb=1 --package=with-dt
sudo ./run_ubuntu.sh --cmdline="console=tty0 loglevel=7" --no-force-cmdline
sudo ./run_ubuntu.sh --pagesize=4096 # Custom boot image pagesize (default 2048)
```

Resume granularity examples (if present in older flow):
```bash
sudo ./build_modular.sh --start-from modules
sudo ./build_modular.sh --start-from busybox
sudo ./build_modular.sh --start-from rootfs
```

### New Flags (Modular)
| Flag | Description |
|------|-------------|
| `--dtb=N` | Select DTB variant index (0,1,2) |
| `--package=catdt|with-dt` | Boot image packaging mode |
| `--cmdline=STR` | Override kernel command line |
| `--no-force-cmdline` | Do not set CONFIG_CMDLINE_FORCE |
| `--pagesize=N` | Override boot image page size (default from stock header or 2048) |
| `--skip-build` | Skip build, flash only |
| `--force-build` | Force rebuild outputs |
| `--skip-backup` | Skip backups (faster, riskier) |
| `--skip-sd-check` | Build without SD detection |
| `--full-verify` | After flashing compute full SHA256 of boot partition (slow) |

### Partition Roles (Typical RG35XX H Internal eMMC)
| Part | Node | Type | Role |
|------|------|------|------|
| p1 | /dev/mmcblk0p1 | FAT / misc | Vendor assets (leave) |
| p2 | /dev/mmcblk0p2 | ext4/raw | System/vendor (leave) |
| p3 | /dev/mmcblk0p3 | raw | Misc/metadata |
| p4 | /dev/mmcblk0p4 | Android boot | Kernel + ramdisk (we flash) |
| p5 | /dev/mmcblk0p5 | ext4 | Root filesystem / modules |

Inspect layout:
```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL /dev/mmcblk0
sgdisk -p /dev/mmcblk0
```

### Fallback / Troubleshooting
Use automatic cycling of DTB variants & packaging modes:
```bash
sudo ./dtb_fallback.sh
```
After each attempt, test boot; script iterates combinations.

Typical remedies for splash loop:
1. Switch DTB variant (`--dtb=`)
2. Switch packaging (`--package=with-dt` or `catdt`)
3. Confirm `--pagesize 2048`
4. Force console cmdline (default) or add UART: `--cmdline="console=tty0 console=ttyS0,115200 earlycon loglevel=7 ignore_loglevel"`

### Recovery
Automatic restore (latest backup set):
```bash
sudo ./restore_backups.sh
```
Manual (if you copied backups elsewhere):
```bash
sudo sgdisk --load-backup=gpt-backup.bin /dev/mmcblk0
sudo dd if=boot-p4-backup.img of=/dev/mmcblk0p4 bs=4M conv=fsync status=progress
sudo dd if=rootfs-p5-backup.img of=/dev/mmcblk0p5 bs=4M conv=fsync status=progress
```
To restore only modules (rootfs mounted at /mnt/p5):
```bash
sudo tar -xzf modules-backup.tar.gz -C /mnt/p5
```

### Integrity & Verification
- Boot image pagesize enforced at build (default 2048) and checked before flash.
- Post-flash hash comparison (first chunk) warns on mismatch.
- Full hash verification optional (read entire p4 and compare to source SHA256).

### Ramdisk Handling
One-shot script extracts stock ramdisk (magiskboot / unmkbootimg / abootimg). Modular path creates a minimal placeholder if extraction not possible. For custom init modifications, unpack the extracted ramdisk, edit, then repack before packaging.

## Configuration

### Kernel Configuration
Edit `config_patch` to customize kernel features:
- WiFi and Bluetooth support
- USB gadget modes
- Development tools
- Custom drivers

### BusyBox Configuration  
Edit `busybox_config_patch` to customize userspace tools (optional).

## Build Process

1. **Dependency Check**: Automatically installs required packages
2. **SD Card Detection**: Finds and validates RG35XX_H SD card
3. **Kernel Building**: Downloads source, applies config, builds kernel and DTBs
4. **BusyBox Building**: Creates minimal userspace
5. **Root Filesystem**: Sets up basic Linux filesystem structure
6. **Flashing**: Writes kernel and rootfs to SD card with progress tracking

## Advanced Features & Developer Tools

### Build Verification & Quality Assurance
- `build_verification.sh` — Comprehensive build output validation, performance testing, and reporting.
- Usage:
  ```bash
  ./build_verification.sh verify      # Validate build outputs
  ./build_verification.sh all         # Full verification and report
  ```

### SD Card Management & Recovery
- `advanced_sd_tools.sh` — Enhanced SD diagnostics, backup, recovery, and optimization.
- Usage:
  ```bash
  ./advanced_sd_tools.sh diagnose     # Run SD diagnostics
  ./advanced_sd_tools.sh backup full  # Full disk backup
  ./advanced_sd_tools.sh recover gpt backups/<dir>  # Restore GPT
  ./advanced_sd_tools.sh optimize     # Optimize SD card
  ```

### Automated Testing Suite
- `automated_testing.sh` — Full environment and build system testing, integration checks, and HTML reporting.
- Usage:
  ```bash
  ./automated_testing.sh all          # Run all tests and generate report
  ./automated_testing.sh quick        # Quick toolchain and build tests
  ./automated_testing.sh performance  # Performance benchmarks
  ```

### Developer Utilities
- `dev_tools.sh` — Clean, status, config, debug, and benchmarking tools for development workflow.
- Usage:
  ```bash
  ./dev_tools.sh status               # Show environment status
  ./dev_tools.sh clean                # Clean build artifacts
  ./dev_tools.sh debug                # Collect debug info
  ./dev_tools.sh benchmark            # Run benchmarks
  ```

### Summary Table of Utilities
| Script                   | Purpose                                      |
|--------------------------|----------------------------------------------|
| build_verification.sh    | Build output validation & reporting           |
| advanced_sd_tools.sh     | SD diagnostics, backup, recovery, optimization|
| automated_testing.sh     | Automated testing & integration checks        |
| dev_tools.sh             | Developer workflow utilities                  |
| dtb_fallback.sh          | Automatic DTB/packaging cycling               |
| restore_backups.sh       | Restore from backup                          |
| test_progress.sh         | Progress bar testing                         |
| install_dependencies.sh  | Install all required build tools              |
| fix_boot_image.sh        | Manual boot image page size fix               |

All scripts are executable and can be run directly from the `new/` directory.

**For full documentation and advanced usage, see the individual script headers and the `ADVANCED_FEATURES_COMPLETE.md` file.**

## Hardware Support

- **Target Device**: Anbernic RG35XX_H handheld
- **SoC**: Allwinner H700 (H616 variant)
- **Architecture**: ARM64 (aarch64)
- **Device Tree**: `sun50i-h700-anbernic-rg35xx-h.dts`

## Development

The modular architecture makes it easy to:
- Add new builders for different components
- Customize flashing procedures
- Extend device support
- Add new configuration options

Each module has a single responsibility and clean interfaces, following SOLID principles.

## Legacy Support

The original monolithic script (`build_rg35xx.sh`) is preserved for compatibility. The new modular system (`build_modular.sh`) is recommended for all new development.

## Contributing

1. Follow the existing modular structure
2. Each new feature should be in its own module
3. Maintain backward compatibility where possible
4. Test on actual RG35XX_H hardware

## License

This project is open source. See individual files for specific licensing information.
