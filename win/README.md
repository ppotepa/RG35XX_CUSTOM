# RG35XX_H Windows Kernel Builder

Experimental script to build the Linux kernel on Windows and send it to Ubuntu for flashing.

## Features

- ✅ **Windows-native**: Builds kernel using WSL2 on your fast Windows machine
- ✅ **Kernel-only**: Builds only the kernel, DTBs, and modules (fastest approach)
- ✅ **Auto-setup**: Downloads and installs all required build tools
- ✅ **Uses config_patch**: Applies your custom kernel configuration automatically
- ✅ **Remote deploy**: Sends built kernel to Ubuntu machine via SSH
- ✅ **Multiple DTB support**: Choose DTB variant for different panel revisions

## Quick Start

```powershell
# Navigate to the win directory
cd new\win

# Basic kernel build and send to Ubuntu
.\build_kernel_win.ps1

# Force rebuild with debug cmdline
.\build_kernel_win.ps1 -ForceRebuild -DebugCmdline

# Build only (don't copy to Ubuntu)
.\build_kernel_win.ps1 -SkipCopy

# Use different DTB variant
.\build_kernel_win.ps1 -DtbVariant 1
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-ForceRebuild` | Force fresh git clone and rebuild | false |
| `-SkipCopy` | Don't copy to Ubuntu machine | false |
| `-DebugCmdline` | Include debug console settings | false |
| `-RemoteHost` | SSH target for Ubuntu machine | root@192.168.100.26 |
| `-RemotePath` | Remote path on Ubuntu | DIY/RG35XX_H/copilot/new |
| `-DtbVariant` | DTB variant index (0,1,2) | 0 |

## DTB Variants

| Index | DTB File | Description |
|-------|----------|-------------|
| 0 | sun50i-h700-anbernic-rg35xx-h.dtb | Standard RG35XX_H |
| 1 | sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb | Rev6 panel variant |
| 2 | sun50i-h700-rg40xx-h.dtb | RG40XX_H variant |

## Prerequisites

The script will automatically install these, but you need:

1. **WSL2** with Ubuntu distribution
2. **SSH access** to your Ubuntu machine
3. **PowerShell 5.1+** (built into Windows 10/11)

If WSL2 is not installed:
```powershell
# Install WSL2 (requires restart)
wsl --install -d Ubuntu
```

## How It Works

1. **Setup**: Checks WSL2 and installs build dependencies in Ubuntu
2. **Source**: Downloads Linux kernel source (linux-6.10.y branch)
3. **Configure**: Applies your `config_patch` and sets kernel cmdline
4. **Build**: Compiles kernel Image, DTBs, and modules using all CPU cores
5. **Package**: Creates combined kernel+dtb image and packages modules
6. **Deploy**: Copies outputs to Ubuntu machine via SSH

## Output Files

Built in `new\win\build\output\`:

- `Image` - Raw kernel image
- `zImage-dtb` - Combined kernel + device tree (ready for boot image)
- `dtb` - Selected device tree blob
- `dtbs/` - All available device tree blobs
- `modules.tar.gz` - Kernel modules archive
- `kernel_info.txt` - Build information

## Ubuntu Integration

After the Windows build completes, on your Ubuntu machine:

```bash
# Create boot image and flash
sudo ./run_ubuntu.sh --skip-kernel --debug-cmdline

# Or just flash if boot image already exists
sudo ./run_ubuntu.sh --skip-build
```

## Performance

Expected build times on modern hardware:
- **First build**: ~5-15 minutes (git clone + full build)
- **Incremental**: ~2-5 minutes (config changes only)
- **Copy to Ubuntu**: ~30 seconds (depends on network)

## Troubleshooting

### WSL Issues
```powershell
# Check WSL status
wsl --list --verbose

# Restart WSL
wsl --shutdown
wsl
```

### SSH Connection Issues
```powershell
# Test SSH connection
ssh root@192.168.100.26 "echo 'SSH works'"

# Use different SSH key
.\build_kernel_win.ps1 -RemoteHost "user@192.168.100.26"
```

### Build Failures
```powershell
# Force clean rebuild
.\build_kernel_win.ps1 -ForceRebuild

# Check WSL build logs
wsl bash -c "cd $(wslpath 'new\win\build\linux') && dmesg"
```

## Advanced Usage

### Custom Remote Configuration
```powershell
# Build for different Ubuntu machine
.\build_kernel_win.ps1 -RemoteHost "dev@192.168.1.100" -RemotePath "/home/dev/rg35xx"
```

### Build for Testing
```powershell
# Build with maximum debugging
.\build_kernel_win.ps1 -DebugCmdline -DtbVariant 1 -ForceRebuild
```

### Local Development
```powershell
# Build without sending to Ubuntu
.\build_kernel_win.ps1 -SkipCopy

# Then manually copy when ready
scp new\win\build\output\* root@192.168.100.26:DIY/RG35XX_H/copilot/new/build/
```

## Integration with Existing Workflow

This script integrates seamlessly with your existing Ubuntu-based flashing workflow:

1. **Windows**: Fast kernel compilation (this script)
2. **Ubuntu**: Boot image creation and device flashing (existing scripts)

The Ubuntu machine continues to handle:
- Boot image creation (`mkbootimg`/`abootimg`)
- Device detection and partition management
- Actual flashing to SD card/eMMC
- Verification and backup operations

This gives you the best of both worlds - fast compilation on Windows, reliable flashing on Ubuntu.
