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
- Ubuntu/Debian system with root access
- SD card with RG35XX_H firmware structure

### Basic Usage

```bash
# Full build with automatic flashing
sudo ./build_modular.sh

# Interactive mode (asks for confirmation)
sudo ./build_modular.sh --interactive

# Just flash an existing kernel
sudo ./build_modular.sh --start-from flash

# Skip backups for faster flashing
sudo ./build_modular.sh --skip-backup
```

### Advanced Options

```bash
# Resume from specific build steps
sudo ./build_modular.sh --start-from modules   # Resume from module installation
sudo ./build_modular.sh --start-from busybox   # Skip kernel, start from BusyBox
sudo ./build_modular.sh --start-from rootfs    # Just create rootfs and flash
```

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
