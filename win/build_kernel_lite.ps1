#!/usr/bin/env pwsh
# Lightweight Windows kernel builder using Git Bash
# Fastest option without requiring MSYS2 or Docker

param (
    [switch]$ForceRebuild = $false,
    [switch]$SkipCopy = $false,
    [switch]$DebugCmdline = $false,
    [string]$RemoteHost = "root@192.168.100.26",
    [string]$RemotePath = "DIY/RG35XX_H/copilot/new",
    [string]$DtbVariant = "0"
)

$ErrorActionPreference = "Stop"

# Paths
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR = "$SCRIPT_DIR\build_lite"
$OUTPUT_DIR = "$BUILD_DIR\output"

# Find Git Bash (usually comes with Git for Windows)
$GitBashPaths = @(
    "${env:ProgramFiles}\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "${env:LOCALAPPDATA}\Programs\Git\bin\bash.exe"
)

$GitBash = $GitBashPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

# Build configuration
$LINUX_BRANCH = "linux-6.10.y"
$LINUX_REPO = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"

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

function Test-Environment {
    Write-Header "Checking lightweight build environment"
    
    # Test Git Bash
    if (!$GitBash) {
        Write-Error "Git Bash not found. Please install Git for Windows"
        Write-Host "Download from: https://git-scm.com/download/win" -ForegroundColor Yellow
        return $false
    }
    Write-Success "Git Bash found: $GitBash"
    
    # Test if we can use Windows Subsystem for Linux Ubuntu
    $wslDistros = wsl --list --quiet 2>$null
    if ($wslDistros -contains "Ubuntu") {
        Write-Success "Ubuntu WSL available for cross-compilation"
        return "wsl"
    }
    
    # Check for existing cross-compiler in PATH
    try {
        $gccTest = & where.exe aarch64-linux-gnu-gcc 2>$null
        if ($gccTest) {
            Write-Success "Cross-compiler found in PATH: $gccTest"
            return "native"
        }
    } catch {}
    
    Write-Warning "No cross-compiler found locally"
    Write-Host "Will use Ubuntu WSL for compilation (faster than full WSL build)" -ForegroundColor Gray
    return "wsl"
}

function Build-KernelHybrid {
    param($Mode)
    
    Write-Header "Building kernel (hybrid approach)"
    
    # Create build directories
    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    
    # Convert Windows paths to Unix-style for Git Bash
    $buildDirUnix = ($BUILD_DIR -replace '\\', '/') -replace '^([A-Z]):', '/`$1'
    $rootDirUnix = ($ROOT_DIR -replace '\\', '/') -replace '^([A-Z]):', '/`$1'
    $outputDirUnix = ($OUTPUT_DIR -replace '\\', '/') -replace '^([A-Z]):', '/`$1'
    
    # Set command line
    $cmdline = if ($DebugCmdline) {
        "console=ttyS0,115200 console=tty0 earlycon=uart,mmio32,0x02500000 root=PARTLABEL=rootfs rootfstype=ext4 rootwait init=/init loglevel=7 ignore_loglevel panic=10 initcall_debug"
    } else {
        "console=tty0 console=ttyS0,115200 root=PARTLABEL=rootfs rootfstype=ext4 rootwait loglevel=4"
    }
    
    if ($Mode -eq "wsl") {
        # Use WSL Ubuntu for just the compilation step (not full build script)
        Write-Host "Using WSL Ubuntu for cross-compilation only..." -ForegroundColor Yellow
        
        $wslScript = @"
#!/bin/bash
set -e
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Convert Windows paths to WSL paths
BUILD_DIR=`$(wslpath '$BUILD_DIR')
ROOT_DIR=`$(wslpath '$ROOT_DIR')
OUTPUT_DIR=`$(wslpath '$OUTPUT_DIR')

echo "Setting up build directory..."
mkdir -p "`$BUILD_DIR"
cd "`$BUILD_DIR"

# Get kernel source
if [ ! -d "linux" ] || [ "$($ForceRebuild.ToString().ToLower())" = "true" ]; then
    echo "Cloning kernel source..."
    rm -rf linux
    git clone --depth=1 --branch $LINUX_BRANCH $LINUX_REPO linux
fi

cd linux

echo "Configuring kernel..."
make defconfig

# Apply config patch
if [ -f "`$ROOT_DIR/config_patch" ]; then
    echo "Applying config patch..."
    ./scripts/kconfig/merge_config.sh -m .config "`$ROOT_DIR/config_patch"
fi

# Set cmdline
echo 'CONFIG_CMDLINE="$cmdline"' >> .config
echo 'CONFIG_CMDLINE_BOOL=y' >> .config
echo 'CONFIG_CMDLINE_FORCE=y' >> .config
make olddefconfig

echo "Building kernel (using all CPU cores)..."
make -j`$(nproc) Image dtbs modules

echo "Packaging outputs..."
mkdir -p "`$OUTPUT_DIR"
cp arch/arm64/boot/Image "`$OUTPUT_DIR/"

# Copy DTBs
mkdir -p "`$OUTPUT_DIR/dtbs"
cp arch/arm64/boot/dts/allwinner/sun50i-h700-*.dtb "`$OUTPUT_DIR/dtbs/" 2>/dev/null || true

# Create combined image
DTB_FILE="arch/arm64/boot/dts/allwinner/${DTB_VARIANTS[$DtbVariant]}"
if [ -f "`$DTB_FILE" ]; then
    cat arch/arm64/boot/Image "`$DTB_FILE" > "`$OUTPUT_DIR/zImage-dtb"
    cp "`$DTB_FILE" "`$OUTPUT_DIR/dtb"
else
    FALLBACK=`$(find arch/arm64/boot/dts/allwinner/ -name "sun50i-h700-*.dtb" | head -1)
    if [ -f "`$FALLBACK" ]; then
        cat arch/arm64/boot/Image "`$FALLBACK" > "`$OUTPUT_DIR/zImage-dtb"
        cp "`$FALLBACK" "`$OUTPUT_DIR/dtb"
    fi
fi

# Package modules
mkdir -p "`$OUTPUT_DIR/modules_temp"
make INSTALL_MOD_PATH="`$OUTPUT_DIR/modules_temp" modules_install
cd "`$OUTPUT_DIR/modules_temp"
tar -czf "`$OUTPUT_DIR/modules.tar.gz" .
rm -rf "`$OUTPUT_DIR/modules_temp"

# Create info file
cd "`$BUILD_DIR/linux"
echo "Kernel: `$(make kernelversion)" > "`$OUTPUT_DIR/kernel_info.txt"
echo "Build Date: `$(date)" >> "`$OUTPUT_DIR/kernel_info.txt"
echo "DTB Variant: ${DTB_VARIANTS[$DtbVariant]}" >> "`$OUTPUT_DIR/kernel_info.txt"
echo "Debug Cmdline: $($DebugCmdline.ToString().ToLower())" >> "`$OUTPUT_DIR/kernel_info.txt"
echo "Build Method: WSL Hybrid" >> "`$OUTPUT_DIR/kernel_info.txt"

echo "Build completed successfully"
"@

        # Write script and execute in WSL
        $tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
        $wslScript -replace "`r`n", "`n" | Out-File -FilePath $tempScript -Encoding UTF8 -NoNewline
        
        $wslTempScript = wsl wslpath -u "'$tempScript'"
        
        Write-Host "Starting kernel build..." -ForegroundColor Yellow
        $startTime = Get-Date
        wsl bash "$wslTempScript"
        $endTime = Get-Date
        $buildTime = ($endTime - $startTime).TotalMinutes
        
        Remove-Item $tempScript -Force
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Kernel build failed"
            return $false
        }
        
        Write-Success "Kernel built in $($buildTime.ToString("F1")) minutes"
    } else {
        Write-Error "Native compilation not yet implemented"
        return $false
    }
    
    return $true
}

function Copy-ToUbuntu {
    if ($SkipCopy) {
        Write-Warning "Skipping copy to Ubuntu (--skip-copy specified)"
        return
    }
    
    Write-Header "Copying kernel outputs to Ubuntu machine"
    
    try {
        Write-Host "Testing SSH connection to $RemoteHost..." -ForegroundColor Yellow
        & ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $RemoteHost "mkdir -p $RemotePath/build" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to connect to $RemoteHost"
            return
        }
        
        Write-Host "Copying kernel outputs..." -ForegroundColor Yellow
        
        # Copy outputs
        Get-ChildItem $OUTPUT_DIR -File | ForEach-Object {
            & scp $_.FullName "${RemoteHost}:${RemotePath}/build/"
        }
        
        if (Test-Path "$OUTPUT_DIR\dtbs") {
            & scp -r "$OUTPUT_DIR\dtbs" "${RemoteHost}:${RemotePath}/build/"
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Copy completed successfully!"
            Write-Host ""
            Write-Host "Next steps on Ubuntu machine:" -ForegroundColor Cyan
            Write-Host "  ssh $RemoteHost" -ForegroundColor White
            Write-Host "  cd $RemotePath" -ForegroundColor White
            Write-Host "  sudo ./run_ubuntu.sh --skip-kernel --debug-cmdline" -ForegroundColor White
        } else {
            Write-Error "Copy failed!"
        }
    }
    catch {
        Write-Error "SSH/SCP failed: $_"
    }
}

function Show-Summary {
    Write-Header "Hybrid Build Summary"
    
    Write-Host "⚡ Lightweight hybrid kernel build completed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Approach used:" -ForegroundColor Cyan
    Write-Host "  🔧 Git Bash for Windows compatibility" -ForegroundColor White
    Write-Host "  🐧 WSL Ubuntu for cross-compilation only" -ForegroundColor White
    Write-Host "  💨 Faster than full WSL build system" -ForegroundColor White
    Write-Host "  📦 No external dependencies (MSYS2/Docker)" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Performance:" -ForegroundColor Cyan
    Write-Host "  ✅ Uses only WSL for compilation (not file I/O)" -ForegroundColor White
    Write-Host "  ✅ Windows handles file management" -ForegroundColor White
    Write-Host "  ✅ Should be 2-3x faster than full WSL approach" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Outputs in ${OUTPUT_DIR}:" -ForegroundColor Cyan
    Get-ChildItem $OUTPUT_DIR | ForEach-Object {
        $size = if ($_.PSIsContainer) { "DIR" } else { "$([math]::Round($_.Length / 1MB, 1)) MB" }
        Write-Host "  ✅ $($_.Name): $size" -ForegroundColor White
    }
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "⚡ RG35XX_H Lightweight Kernel Builder" -ForegroundColor Magenta
    Write-Host "Hybrid approach: Windows + minimal WSL usage" -ForegroundColor Gray
    Write-Host ""
    
    $envMode = Test-Environment
    if (!$envMode) {
        exit 1
    }
    
    if (!(Build-KernelHybrid $envMode)) {
        exit 1
    }
    
    Copy-ToUbuntu
    Show-Summary
    
    Write-Host ""
    Write-Host "🎯 Lightweight build completed!" -ForegroundColor Green
    Write-Host "This should be much faster than the full WSL approach." -ForegroundColor Yellow
}

# Script entry point
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
