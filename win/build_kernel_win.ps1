#!/usr/bin/env pwsh
# RG35XX_H Windows Kernel Build Script
# Builds ONLY the kernel on Windows and sends to Ubuntu for flashing

param (
    [switch]$ForceRebuild = $false,
    [switch]$SkipCopy = $false,
    [switch]$DebugCmdline = $false,
    [string]$RemoteHost = "root@192.168.100.26",
    [string]$RemotePath = "DIY/RG35XX_H/copilot/new",
    [string]$DtbVariant = "0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Paths
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR = "$SCRIPT_DIR\build"
$LINUX_DIR = "$BUILD_DIR\linux"
$OUTPUT_DIR = "$BUILD_DIR\output"

# Build configuration
$LINUX_BRANCH = "linux-6.10.y"
$LINUX_REPO = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
$CROSS_COMPILE = "aarch64-linux-gnu-"
$ARCH = "arm64"

# DTB variants
$DTB_VARIANTS = @(
    "sun50i-h700-anbernic-rg35xx-h.dtb",
    "sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb", 
    "sun50i-h700-rg40xx-h.dtb"
)

function Write-Header {
    param($Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param($Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param($Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param($Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Test-WSL {
    Write-Header "Checking WSL availability"
    
    try {
        $wslVersion = wsl --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "WSL not available. Please install WSL2 with Ubuntu"
            Write-Host "Run: wsl --install -d Ubuntu" -ForegroundColor Yellow
            exit 1
        }
        Write-Success "WSL is available"
        
        # Check if Ubuntu is installed
        $distros = wsl --list --quiet
        if ($distros -notcontains "Ubuntu") {
            Write-Warning "Ubuntu not found in WSL. Installing..."
            wsl --install -d Ubuntu
            Write-Host "Please restart your computer and run this script again" -ForegroundColor Yellow
            exit 1
        }
        Write-Success "Ubuntu distribution found"
    }
    catch {
        Write-Error "Failed to check WSL: $_"
        exit 1
    }
}

function Install-Dependencies {
    Write-Header "Installing build dependencies in WSL"
    
    # Create a temporary script file to avoid line ending issues
    $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
    
    $setupScript = @'
#!/bin/bash
set -e

echo "Updating package lists..."
sudo apt-get update -qq

echo "Installing build dependencies..."
sudo apt-get install -y \
    git make gcc bc bison flex libssl-dev libelf-dev \
    gcc-aarch64-linux-gnu wget curl tar rsync cpio \
    util-linux e2fsprogs device-tree-compiler \
    build-essential ca-certificates pv ccache \
    abootimg mkbootimg android-sdk-libsparse-utils \
    openssh-client

# Try to install android tools, fallback if not available
if ! sudo apt-get install -y android-tools-mkbootimg 2>/dev/null; then
    echo "Using mkbootimg as fallback for android-tools-mkbootimg"
fi

if ! sudo apt-get install -y android-tools-fsutils 2>/dev/null; then
    echo "Using android-sdk-libsparse-utils as fallback"
fi

echo "Build dependencies installed successfully"
'@

    # Write script with Unix line endings
    $setupScript -replace "`r`n", "`n" | Out-File -FilePath $tempScript -Encoding UTF8 -NoNewline
    
    # Convert to WSL path and execute
    $wslTempScript = wsl wslpath -u "'$tempScript'"
    wsl bash "$wslTempScript"
    
    # Clean up
    Remove-Item $tempScript -Force
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install dependencies"
        exit 1
    }
    Write-Success "Dependencies installed"
}

function Get-LinuxSource {
    Write-Header "Getting Linux kernel source"
    
    # Create a temporary script file
    $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
    
    $getSourceScript = @"
#!/bin/bash
set -e
cd `$(wslpath '$BUILD_DIR')

if [[ ! -d "linux" ]] || [[ "$($ForceRebuild.ToString().ToLower())" == "true" ]]; then
    echo "Cloning Linux kernel source..."
    rm -rf linux
    git clone --depth=1 --branch $LINUX_BRANCH $LINUX_REPO linux
    echo "Kernel source cloned successfully"
else
    echo "Using existing Linux source"
    cd linux
    echo "Updating kernel source..."
    git fetch --depth=1 origin $LINUX_BRANCH || true
    git reset --hard FETCH_HEAD || true
fi
"@

    # Write script with Unix line endings
    $getSourceScript -replace "`r`n", "`n" | Out-File -FilePath $tempScript -Encoding UTF8 -NoNewline
    
    # Execute in WSL
    $wslTempScript = wsl wslpath -u "'$tempScript'"
    wsl bash "$wslTempScript"
    
    # Clean up
    Remove-Item $tempScript -Force

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get Linux source"
        exit 1
    }
    Write-Success "Linux source ready"
}

function Configure-Kernel {
    Write-Header "Configuring kernel"
    
    # Copy config patch to WSL accessible location
    $configPatchPath = "$ROOT_DIR\config_patch"
    $wslConfigPath = wsl wslpath "'$configPatchPath'"
    
    # Create a temporary script file
    $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
    
    $configScript = @"
#!/bin/bash
set -e
cd `$(wslpath '$LINUX_DIR')

export ARCH=$ARCH
export CROSS_COMPILE=$CROSS_COMPILE

echo "Creating base config..."
make defconfig

echo "Applying custom configuration from config_patch..."
if [[ -f "$wslConfigPath" ]]; then
    echo "Found config_patch, merging..."
    ./scripts/kconfig/merge_config.sh -m .config "$wslConfigPath"
else
    echo "Warning: config_patch not found at $wslConfigPath"
fi

# Set command line
if [[ "$($DebugCmdline.ToString().ToLower())" == "true" ]]; then
    CMDLINE="console=ttyS0,115200 console=tty0 earlycon=uart,mmio32,0x02500000 root=PARTLABEL=rootfs rootfstype=ext4 rootwait init=/init loglevel=7 ignore_loglevel panic=10 initcall_debug"
else
    CMDLINE="console=tty0 console=ttyS0,115200 root=PARTLABEL=rootfs rootfstype=ext4 rootwait loglevel=4"
fi

echo "Setting kernel cmdline: \$CMDLINE"
echo "CONFIG_CMDLINE=\"\$CMDLINE\"" >> .config
echo "CONFIG_CMDLINE_BOOL=y" >> .config
echo "CONFIG_CMDLINE_FORCE=y" >> .config

echo "Resolving configuration dependencies..."
make olddefconfig

echo "Kernel configuration completed"
"@

    # Write script with Unix line endings
    $configScript -replace "`r`n", "`n" | Out-File -FilePath $tempScript -Encoding UTF8 -NoNewline
    
    # Execute in WSL
    $wslTempScript = wsl wslpath -u "'$tempScript'"
    wsl bash "$wslTempScript"
    
    # Clean up
    Remove-Item $tempScript -Force

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure kernel"
        exit 1
    }
    Write-Success "Kernel configured"
}

function Build-Kernel {
    Write-Header "Building kernel"
    
    $cores = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    $buildJobs = $cores + 2
    Write-Host "Building with $buildJobs parallel jobs (CPU cores: $cores)" -ForegroundColor Yellow
    
    # Create a temporary script file
    $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
    
    $buildScript = @"
#!/bin/bash
set -e
cd `$(wslpath '$LINUX_DIR')

export ARCH=$ARCH
export CROSS_COMPILE=$CROSS_COMPILE

echo "Building kernel Image..."
make -j$buildJobs Image

echo "Building device trees..."
make -j$buildJobs dtbs

echo "Building kernel modules..."
make -j$buildJobs modules

echo "Kernel build completed successfully"
"@

    # Write script with Unix line endings
    $buildScript -replace "`r`n", "`n" | Out-File -FilePath $tempScript -Encoding UTF8 -NoNewline
    
    # Execute in WSL
    $wslTempScript = wsl wslpath -u "'$tempScript'"
    wsl bash "$wslTempScript"
    
    # Clean up
    Remove-Item $tempScript -Force

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build kernel"
        exit 1
    }
    Write-Success "Kernel built successfully"
}

function Package-KernelOutputs {
    Write-Header "Packaging kernel outputs"
    
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    
    # Create a temporary script file
    $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
    
    $packageScript = @"
#!/bin/bash
set -e
cd `$(wslpath '$LINUX_DIR')
OUTPUT_WSL=`$(wslpath '$OUTPUT_DIR')

echo "Creating output directory..."
mkdir -p "\$OUTPUT_WSL"

echo "Copying kernel Image..."
cp arch/arm64/boot/Image "\$OUTPUT_WSL/"

echo "Copying device trees..."
mkdir -p "\$OUTPUT_WSL/dtbs"
cp arch/arm64/boot/dts/allwinner/sun50i-h700-*.dtb "\$OUTPUT_WSL/dtbs/" 2>/dev/null || true

# Create combined kernel+dtb image (catdt mode)
DTB_FILE="arch/arm64/boot/dts/allwinner/${DTB_VARIANTS[$DtbVariant]}"
if [[ -f "\$DTB_FILE" ]]; then
    echo "Creating combined kernel+dtb image with \$DTB_FILE..."
    cat arch/arm64/boot/Image "\$DTB_FILE" > "\$OUTPUT_WSL/zImage-dtb"
    cp "\$DTB_FILE" "\$OUTPUT_WSL/dtb"
else
    echo "Warning: DTB file \$DTB_FILE not found"
    # Use first available DTB as fallback
    FALLBACK_DTB=`$(find arch/arm64/boot/dts/allwinner/ -name "sun50i-h700-*.dtb" | head -1)
    if [[ -f "\$FALLBACK_DTB" ]]; then
        echo "Using fallback DTB: \$FALLBACK_DTB"
        cat arch/arm64/boot/Image "\$FALLBACK_DTB" > "\$OUTPUT_WSL/zImage-dtb"
        cp "\$FALLBACK_DTB" "\$OUTPUT_WSL/dtb"
    fi
fi

echo "Packaging kernel modules..."
mkdir -p "\$OUTPUT_WSL/modules_temp"
make INSTALL_MOD_PATH="\$OUTPUT_WSL/modules_temp" modules_install
cd "\$OUTPUT_WSL/modules_temp"
tar -czf "\$OUTPUT_WSL/modules.tar.gz" .
rm -rf "\$OUTPUT_WSL/modules_temp"

echo "Creating kernel info file..."
cd `$(wslpath '$LINUX_DIR')
echo "Kernel: \$(make kernelversion)" > "\$OUTPUT_WSL/kernel_info.txt"
echo "Build Date: \$(date)" >> "\$OUTPUT_WSL/kernel_info.txt"
echo "DTB Variant: ${DTB_VARIANTS[$DtbVariant]}" >> "\$OUTPUT_WSL/kernel_info.txt"
echo "Debug Cmdline: $($DebugCmdline.ToString().ToLower())" >> "\$OUTPUT_WSL/kernel_info.txt"

echo "Kernel outputs packaged successfully"
"@

    # Write script with Unix line endings
    $packageScript -replace "`r`n", "`n" | Out-File -FilePath $tempScript -Encoding UTF8 -NoNewline
    
    # Execute in WSL
    $wslTempScript = wsl wslpath -u "'$tempScript'"
    wsl bash "$wslTempScript"
    
    # Clean up
    Remove-Item $tempScript -Force

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to package kernel outputs"
        exit 1
    }
    Write-Success "Kernel outputs packaged"
}

function Copy-ToUbuntu {
    if ($SkipCopy) {
        Write-Warning "Skipping copy to Ubuntu (--skip-copy specified)"
        return
    }
    
    Write-Header "Copying kernel outputs to Ubuntu machine"
    
    # Create control socket for SSH connection reuse
    $controlPath = "ssh-control-socket-$([System.IO.Path]::GetRandomFileName())"
    $sshOpts = @(
        "-o", "ControlMaster=auto",
        "-o", "ControlPath=$controlPath", 
        "-o", "ControlPersist=10s",
        "-o", "StrictHostKeyChecking=no"
    )
    
    try {
        Write-Host "Establishing SSH connection to $RemoteHost..." -ForegroundColor Yellow
        & ssh @sshOpts $RemoteHost "mkdir -p $RemotePath/build" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to establish SSH connection to $RemoteHost"
            return
        }
        
        Write-Host "Copying kernel outputs..." -ForegroundColor Yellow
        
        # Copy kernel Image
        & scp @sshOpts "$OUTPUT_DIR/Image" "${RemoteHost}:${RemotePath}/build/"
        
        # Copy combined kernel+dtb
        if (Test-Path "$OUTPUT_DIR/zImage-dtb") {
            & scp @sshOpts "$OUTPUT_DIR/zImage-dtb" "${RemoteHost}:${RemotePath}/build/"
        }
        
        # Copy DTB
        if (Test-Path "$OUTPUT_DIR/dtb") {
            & scp @sshOpts "$OUTPUT_DIR/dtb" "${RemoteHost}:${RemotePath}/build/"
        }
        
        # Copy modules
        if (Test-Path "$OUTPUT_DIR/modules.tar.gz") {
            & scp @sshOpts "$OUTPUT_DIR/modules.tar.gz" "${RemoteHost}:${RemotePath}/build/"
        }
        
        # Copy DTBs directory
        if (Test-Path "$OUTPUT_DIR/dtbs") {
            & scp @sshOpts -r "$OUTPUT_DIR/dtbs" "${RemoteHost}:${RemotePath}/build/"
        }
        
        # Copy info file
        if (Test-Path "$OUTPUT_DIR/kernel_info.txt") {
            & scp @sshOpts "$OUTPUT_DIR/kernel_info.txt" "${RemoteHost}:${RemotePath}/build/"
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Copy completed successfully!"
            Write-Host ""
            Write-Host "Kernel outputs copied to Ubuntu machine." -ForegroundColor Cyan
            Write-Host "To create boot image and flash:" -ForegroundColor Cyan
            Write-Host "  ssh $RemoteHost" -ForegroundColor White
            Write-Host "  cd $RemotePath" -ForegroundColor White
            Write-Host "  sudo ./run_ubuntu.sh --skip-kernel --debug-cmdline" -ForegroundColor White
            Write-Host ""
            Write-Host "Or to flash existing boot image:" -ForegroundColor Cyan  
            Write-Host "  sudo ./run_ubuntu.sh --skip-build" -ForegroundColor White
        } else {
            Write-Error "Copy failed!"
        }
    }
    finally {
        # Clean up SSH connection
        & ssh @sshOpts -O exit $RemoteHost 2>$null | Out-Null
        if (Test-Path $controlPath) { 
            Remove-Item $controlPath -Force 2>$null | Out-Null 
        }
    }
}

function Show-Summary {
    Write-Header "Build Summary"
    
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Outputs created:" -ForegroundColor Cyan
    if (Test-Path "$OUTPUT_DIR/Image") {
        $imageSize = (Get-Item "$OUTPUT_DIR/Image").Length / 1MB
        Write-Host "  ✅ Kernel Image: $OUTPUT_DIR/Image ($($imageSize.ToString("F1")) MB)" -ForegroundColor White
    }
    if (Test-Path "$OUTPUT_DIR/zImage-dtb") {
        $combinedSize = (Get-Item "$OUTPUT_DIR/zImage-dtb").Length / 1MB  
        Write-Host "  ✅ Combined Image+DTB: $OUTPUT_DIR/zImage-dtb ($($combinedSize.ToString("F1")) MB)" -ForegroundColor White
    }
    if (Test-Path "$OUTPUT_DIR/modules.tar.gz") {
        $modulesSize = (Get-Item "$OUTPUT_DIR/modules.tar.gz").Length / 1MB
        Write-Host "  ✅ Kernel Modules: $OUTPUT_DIR/modules.tar.gz ($($modulesSize.ToString("F1")) MB)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    if (!$SkipCopy) {
        Write-Host "  1. SSH to Ubuntu machine: ssh $RemoteHost" -ForegroundColor White
        Write-Host "  2. Create boot image and flash: sudo ./run_ubuntu.sh --skip-kernel" -ForegroundColor White
    } else {
        Write-Host "  1. Copy outputs to Ubuntu machine manually" -ForegroundColor White
        Write-Host "  2. Create boot image and flash on Ubuntu" -ForegroundColor White
    }
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "🚀 RG35XX_H Windows Kernel Builder" -ForegroundColor Magenta
    Write-Host "Building kernel on Windows, sending to Ubuntu for flashing" -ForegroundColor Gray
    Write-Host ""
    
    # Create directories
    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
    
    # Execute build steps
    Test-WSL
    Install-Dependencies  
    Get-LinuxSource
    Configure-Kernel
    Build-Kernel
    Package-KernelOutputs
    Copy-ToUbuntu
    Show-Summary
    
    Write-Host ""
    Write-Host "🎉 Kernel build process completed!" -ForegroundColor Green
}

# Script entry point
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
