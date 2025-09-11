# RG35XX-H Custom Linux Builder (Plugin-Based Architecture)

A robust, modular build system for creating custom Linux builds for the Anbernic RG35XX-H handheld device with a focus on LCD console visibility during boot.

## Plugin Architecture Overview

The project is now organized into a plugin-based architecture for better maintainability and extensibility:

```
RG35XX-H/
├── config/           # Configuration files
│   ├── constants.sh  # Shared constants
│   └── *_patch       # Kernel/busybox patches
│
├── core/             # Core build functionality
│   ├── build.sh      # Standard build process
│   ├── build_rg35xxh.sh  # RG35XX-H specific build
│   └── install_dependencies.sh  # Dependency installation
│
├── lib/              # Shared libraries
│   ├── logger.sh     # Logging utilities
│   ├── system.sh     # System utilities
│   └── device_utils.sh  # Device detection utilities
│
├── modules/          # Functional modules
│   └── kernel.sh     # Kernel build module
│
├── builders/         # Builder implementations
│   ├── kernel_builder.sh    # Kernel build process
│   ├── busybox_builder.sh   # BusyBox build process
│   └── rootfs_builder.sh    # Root filesystem builder
│
├── plugins/          # Plugin extensions
│   ├── backup/       # Backup utilities
│   ├── diagnostics/  # Diagnostic tools
│   ├── sd_tools/     # SD card management
│   └── verification/ # Build verification
│
├── tools/            # Standalone tools
│   └── fix_boot_image.sh  # Boot image fixing tool
│
├── docs/             # Documentation
└── main.sh           # Main entry point
```

## Features

- **Modular Design**: Easily extend with new plugins
- **Research-Based Fixes**: LCD console visibility during boot
- **Optimized Build Process**: ccache integration and parallel compilation
- **Robust Error Handling**: Comprehensive error detection and reporting

## Getting Started

### Prerequisites

- Ubuntu 20.04 or later (WSL works too!)
- 10GB+ free disk space
- Internet connection for downloading sources

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/RG35XX-H.git
   cd RG35XX-H
   ```

2. Run the main script:
   ```bash
   ./main.sh --build-rg35xxh
   ```

### Available Commands

- `./main.sh --build-rg35xxh` - Build RG35XX-H Linux with LCD console fixes
- `./main.sh --install-deps` - Install required dependencies
- `./main.sh --backup` - Backup the SD card
- `./main.sh --restore` - Restore from backup
- `./main.sh --diagnose` - Run SD card diagnostics
- `./main.sh --verify` - Verify the build

## LCD Console Visibility Features

This build includes research-backed fixes for:
- LCD console visibility during boot
- Proper framebuffer console configuration
- Allwinner H700 display pipeline support
- Optimized kernel command line parameters

## Contributing

Contributions are welcome! To add a new plugin:

1. Create a new directory under `plugins/`
2. Implement your functionality
3. Update `main.sh` to include your new plugin

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Knulli project for framebuffer research
- linux-sunxi.org community
- Allwinner H700 documentation contributors
