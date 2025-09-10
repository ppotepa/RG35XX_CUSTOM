#!/usr/bin/env pwsh
# Native Windows Kernel Builder for RG35XX_H
# Uses MSYS2/MinGW64 for maximum performance on Windows

param (
    [switch]$ForceRebuild = $false,
    [switch]$SkipCopy = $false,
    [switch]$DebugCmdline = $false,
    [switch]$InstallMsys2 = $false,
    [string]$RemoteHost = "root@192.168.100.26",
    [string]$RemotePath = "DIY/RG35XX_H/copilot/new",
    [string]$DtbVariant = "0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Paths
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR = "$SCRIPT_DIR\build_native"
$LINUX_DIR = "$BUILD_DIR\linux"
$OUTPUT_DIR = "$BUILD_DIR\output"

# MSYS2 paths
$MSYS2_ROOT = "C:\msys64"
$MSYS2_BIN = "$MSYS2_ROOT\usr\bin"
$MINGW64_BIN = "$MSYS2_ROOT\mingw64\bin"

# Build configuration
$LINUX_BRANCH = "linux-6.10.y"
$LINUX_REPO = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
$CROSS_COMPILE = "aarch64-none-linux-gnu-"
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

function Install-MSYS2 {
    if ($InstallMsys2 -or !(Test-Path $MSYS2_ROOT)) {
        Write-Header "Installing MSYS2"
        
        $msys2Installer = "$env:TEMP\msys2-x86_64-latest.exe"
        Write-Host "Downloading MSYS2 installer..." -ForegroundColor Yellow
        
        Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe" -OutFile $msys2Installer
        
        Write-Host "Installing MSYS2 (this may take a few minutes)..." -ForegroundColor Yellow
        Start-Process -FilePath $msys2Installer -ArgumentList "--confirm-command", "--accept-messages", "--root", "C:\msys64" -Wait
        
        Remove-Item $msys2Installer -Force
        Write-Success "MSYS2 installed"
    } else {
        Write-Success "MSYS2 already installed"
    }
}

function Install-Toolchain {
    Write-Header "Setting up build toolchain"
    
    # Update MSYS2 and install packages
    $msys2_cmd = "$MSYS2_BIN\bash.exe"
    
    Write-Host "Updating MSYS2 packages..." -ForegroundColor Yellow
    & $msys2_cmd -lc "pacman --noconfirm -Syu"
    
    Write-Host "Installing build tools..." -ForegroundColor Yellow
    & $msys2_cmd -lc "pacman --noconfirm -S base-devel git mingw-w64-x86_64-toolchain"
    
    Write-Host "Installing ARM64 cross-compiler..." -ForegroundColor Yellow
    & $msys2_cmd -lc "pacman --noconfirm -S mingw-w64-x86_64-aarch64-elf-toolchain"
    
    # Alternative: download and extract prebuilt toolchain if pacman version doesn't work
    $toolchainPath = "$MSYS2_ROOT\opt\aarch64-none-linux-gnu"
    if (!(Test-Path "$toolchainPath\bin\aarch64-none-linux-gnu-gcc.exe")) {
        Write-Host "Installing ARM Embedded toolchain..." -ForegroundColor Yellow
        $toolchainUrl = "https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-mingw-w64-i686-aarch64-none-linux-gnu.zip"
        $toolchainZip = "$env:TEMP\arm-toolchain.zip"
        
        Write-Host "Downloading ARM toolchain (this is large, ~150MB)..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $toolchainUrl -OutFile $toolchainZip -UseBasicParsing
        
        Write-Host "Extracting toolchain..." -ForegroundColor Yellow
        Expand-Archive -Path $toolchainZip -DestinationPath "$MSYS2_ROOT\opt" -Force
        
        # Rename extracted directory
        $extractedDir = Get-ChildItem "$MSYS2_ROOT\opt" -Directory | Where-Object { $_.Name -like "arm-gnu-toolchain*aarch64-none-linux-gnu" } | Select-Object -First 1
        if ($extractedDir) {
            Move-Item $extractedDir.FullName $toolchainPath -Force
        }
        
        Remove-Item $toolchainZip -Force
    }
    
    Write-Success "Toolchain installed"
}

function Test-Environment {
    Write-Header "Testing build environment"
    
    # Test MSYS2
    if (!(Test-Path $MSYS2_BIN\bash.exe)) {
        Write-Error "MSYS2 bash not found. Please install MSYS2 first."
        return $false
    }
    
    # Test cross-compiler
    $env:PATH = "$MSYS2_ROOT\opt\aarch64-none-linux-gnu\bin;$MINGW64_BIN;$MSYS2_BIN;$env:PATH"
    
    try {
        $gccTest = & "$MSYS2_ROOT\opt\aarch64-none-linux-gnu\bin\aarch64-none-linux-gnu-gcc.exe" --version 2>$null
        if ($gccTest) {
            Write-Success "Cross-compiler found"
        } else {
            Write-Warning "Cross-compiler not found, will install"
            Install-Toolchain
        }
    } catch {
        Write-Warning "Cross-compiler test failed, will install"
        Install-Toolchain
    }
    
    return $true
}

function Get-LinuxSource {
    Write-Header "Getting Linux kernel source"
    
    $msys2_cmd = "$MSYS2_BIN\bash.exe"
    $env:PATH = "$MINGW64_BIN;$MSYS2_BIN;$env:PATH"
    
    if (!(Test-Path $LINUX_DIR) -or $ForceRebuild) {
        Write-Host "Cloning Linux kernel source..." -ForegroundColor Yellow
        
        if (Test-Path $LINUX_DIR) {
            Remove-Item $LINUX_DIR -Recurse -Force
        }
        
        New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
        
        # Use git from MSYS2
        & $msys2_cmd -lc "cd '$($BUILD_DIR -replace '\\','/')' && git clone --depth=1 --branch $LINUX_BRANCH $LINUX_REPO linux"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to clone Linux source"
            return $false
        }
    } else {
        Write-Host "Using existing Linux source" -ForegroundColor Yellow
        & $msys2_cmd -lc "cd '$($LINUX_DIR -replace '\\','/')' && git fetch --depth=1 origin $LINUX_BRANCH && git reset --hard FETCH_HEAD"
    }
    
    Write-Success "Linux source ready"
    return $true
}

function Set-KernelConfiguration {
    Write-Header "Configuring kernel"
    
    $msys2_cmd = "$MSYS2_BIN\bash.exe"
    $env:PATH = "$MSYS2_ROOT\opt\aarch64-none-linux-gnu\bin;$MINGW64_BIN;$MSYS2_BIN;$env:PATH"
    
    # Convert paths for MSYS2
    $linuxPath = $LINUX_DIR -replace '\\','/'
    $configPatchPath = "$ROOT_DIR\config_patch" -replace '\\','/'
    
    # Set command line based on debug flag
    $cmdline = if ($DebugCmdline) {
        "console=ttyS0,115200 console=tty0 earlycon=uart,mmio32,0x02500000 root=PARTLABEL=rootfs rootfstype=ext4 rootwait init=/init loglevel=7 ignore_loglevel panic=10 initcall_debug"
    } else {
        "console=tty0 console=ttyS0,115200 root=PARTLABEL=rootfs rootfstype=ext4 rootwait loglevel=4"
    }
    
    # Configure kernel
    $configScript = @"
export ARCH=$ARCH
export CROSS_COMPILE=$CROSS_COMPILE
export PATH=`$PATH:/opt/aarch64-none-linux-gnu/bin

cd '$linuxPath'

echo "Creating base config..."
make defconfig

echo "Applying custom configuration..."
if [ -f '$configPatchPath' ]; then
    echo "Found config_patch, merging..."
    ./scripts/kconfig/merge_config.sh -m .config '$configPatchPath'
else
    echo "Warning: config_patch not found"
fi

echo "Setting kernel cmdline: $cmdline"
echo 'CONFIG_CMDLINE="$cmdline"' >> .config
echo 'CONFIG_CMDLINE_BOOL=y' >> .config
echo 'CONFIG_CMDLINE_FORCE=y' >> .config

echo "Resolving dependencies..."
make olddefconfig

echo "Kernel configuration completed"
"@

    & $msys2_cmd -lc $configScript
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to configure kernel"
        return $false
    }
    
    Write-Success "Kernel configured"
    return $true
}

function Build-Kernel {
    Write-Header "Building kernel"
    
    $cores = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    $buildJobs = $cores + 2
    Write-Host "Building with $buildJobs parallel jobs (CPU cores: $cores)" -ForegroundColor Yellow
    
    $msys2_cmd = "$MSYS2_BIN\bash.exe"
    $env:PATH = "$MSYS2_ROOT\opt\aarch64-none-linux-gnu\bin;$MINGW64_BIN;$MSYS2_BIN;$env:PATH"
    
    $linuxPath = $LINUX_DIR -replace '\\','/'
    
    $buildScript = @"
export ARCH=$ARCH
export CROSS_COMPILE=$CROSS_COMPILE
export PATH=`$PATH:/opt/aarch64-none-linux-gnu/bin

cd '$linuxPath'

echo "Building kernel Image..."
make -j$buildJobs Image

echo "Building device trees..."
make -j$buildJobs dtbs

echo "Building kernel modules..."
make -j$buildJobs modules

echo "Kernel build completed"
"@

    $startTime = Get-Date
    & $msys2_cmd -lc $buildScript
    $endTime = Get-Date
    $buildTime = ($endTime - $startTime).TotalMinutes
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build kernel"
        return $false
    }
    
    Write-Success "Kernel built successfully in $($buildTime.ToString("F1")) minutes"
    return $true
}

function New-KernelPackage {
    Write-Header "Packaging kernel outputs"
    
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    
    $msys2_cmd = "$MSYS2_BIN\bash.exe"
    $linuxPath = $LINUX_DIR -replace '\\','/'
    $outputPath = $OUTPUT_DIR -replace '\\','/'
    
    $packageScript = @"
cd '$linuxPath'

echo "Creating output directory..."
mkdir -p '$outputPath'

echo "Copying kernel Image..."
cp arch/arm64/boot/Image '$outputPath/'

echo "Copying device trees..."
mkdir -p '$outputPath/dtbs'
cp arch/arm64/boot/dts/allwinner/sun50i-h700-*.dtb '$outputPath/dtbs/' 2>/dev/null || true

# Create combined kernel+dtb image
DTB_FILE="arch/arm64/boot/dts/allwinner/${DTB_VARIANTS[$DtbVariant]}"
if [ -f "`$DTB_FILE" ]; then
    echo "Creating combined kernel+dtb with `$DTB_FILE..."
    cat arch/arm64/boot/Image "`$DTB_FILE" > '$outputPath/zImage-dtb'
    cp "`$DTB_FILE" '$outputPath/dtb'
else
    echo "Warning: DTB `$DTB_FILE not found, using fallback"
    FALLBACK_DTB=`$(find arch/arm64/boot/dts/allwinner/ -name "sun50i-h700-*.dtb" | head -1)
    if [ -f "`$FALLBACK_DTB" ]; then
        cat arch/arm64/boot/Image "`$FALLBACK_DTB" > '$outputPath/zImage-dtb'
        cp "`$FALLBACK_DTB" '$outputPath/dtb'
    fi
fi

echo "Packaging modules..."
mkdir -p '$outputPath/modules_temp'
make INSTALL_MOD_PATH='$outputPath/modules_temp' modules_install
cd '$outputPath/modules_temp'
tar -czf '$outputPath/modules.tar.gz' .
rm -rf '$outputPath/modules_temp'

echo "Creating build info..."
cd '$linuxPath'
echo "Kernel: `$(make kernelversion)" > '$outputPath/kernel_info.txt'
echo "Build Date: `$(date)" >> '$outputPath/kernel_info.txt'
echo "DTB Variant: ${DTB_VARIANTS[$DtbVariant]}" >> '$outputPath/kernel_info.txt'
echo "Debug Cmdline: $($DebugCmdline.ToString().ToLower())" >> '$outputPath/kernel_info.txt'
echo "Build Host: Windows Native (MSYS2)" >> '$outputPath/kernel_info.txt'

echo "Packaging completed"
"@

    & $msys2_cmd -lc $packageScript
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to package outputs"
        return $false
    }
    
    Write-Success "Kernel outputs packaged"
    return $true
}

function Copy-ToUbuntu {
    if ($SkipCopy) {
        Write-Warning "Skipping copy to Ubuntu (--skip-copy specified)"
        return
    }
    
    Write-Header "Copying kernel outputs to Ubuntu machine"
    
    # Use Windows native SSH (should be available in Windows 10/11)
    try {
        Write-Host "Testing SSH connection to $RemoteHost..." -ForegroundColor Yellow
        & ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $RemoteHost "mkdir -p $RemotePath/build" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to connect to $RemoteHost"
            return
        }
        
        Write-Host "Copying kernel outputs..." -ForegroundColor Yellow
        
        # Copy files
        & scp "$OUTPUT_DIR/Image" "${RemoteHost}:${RemotePath}/build/"
        if (Test-Path "$OUTPUT_DIR/zImage-dtb") {
            & scp "$OUTPUT_DIR/zImage-dtb" "${RemoteHost}:${RemotePath}/build/"
        }
        if (Test-Path "$OUTPUT_DIR/dtb") {
            & scp "$OUTPUT_DIR/dtb" "${RemoteHost}:${RemotePath}/build/"
        }
        if (Test-Path "$OUTPUT_DIR/modules.tar.gz") {
            & scp "$OUTPUT_DIR/modules.tar.gz" "${RemoteHost}:${RemotePath}/build/"
        }
        if (Test-Path "$OUTPUT_DIR/dtbs") {
            & scp -r "$OUTPUT_DIR/dtbs" "${RemoteHost}:${RemotePath}/build/"
        }
        if (Test-Path "$OUTPUT_DIR/kernel_info.txt") {
            & scp "$OUTPUT_DIR/kernel_info.txt" "${RemoteHost}:${RemotePath}/build/"
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
        Write-Host "Make sure OpenSSH client is installed on Windows" -ForegroundColor Yellow
    }
}

function Show-Summary {
    Write-Header "Build Summary"
    
    Write-Host "🎉 Native Windows kernel build completed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Build performance:" -ForegroundColor Cyan
    Write-Host "  ⚡ Native Windows compilation (no WSL overhead)" -ForegroundColor White
    Write-Host "  🚀 MSYS2/MinGW64 toolchain" -ForegroundColor White
    Write-Host "  💨 All CPU cores utilized ($((Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors + 2) jobs)" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Outputs created in ${OUTPUT_DIR}:" -ForegroundColor Cyan
    
    if (Test-Path "$OUTPUT_DIR/Image") {
        $imageSize = (Get-Item "$OUTPUT_DIR/Image").Length / 1MB
        Write-Host "  ✅ Kernel Image: $($imageSize.ToString("F1")) MB" -ForegroundColor White
    }
    if (Test-Path "$OUTPUT_DIR/zImage-dtb") {
        $combinedSize = (Get-Item "$OUTPUT_DIR/zImage-dtb").Length / 1MB  
        Write-Host "  ✅ Combined Image+DTB: $($combinedSize.ToString("F1")) MB" -ForegroundColor White
    }
    if (Test-Path "$OUTPUT_DIR/modules.tar.gz") {
        $modulesSize = (Get-Item "$OUTPUT_DIR/modules.tar.gz").Length / 1MB
        Write-Host "  ✅ Kernel Modules: $($modulesSize.ToString("F1")) MB" -ForegroundColor White
    }
    if (Test-Path "$OUTPUT_DIR/kernel_info.txt") {
        Write-Host "  ✅ Build Info: kernel_info.txt" -ForegroundColor White
    }
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "🚀 RG35XX_H Native Windows Kernel Builder" -ForegroundColor Magenta
    Write-Host "High-performance native Windows compilation using MSYS2" -ForegroundColor Gray
    Write-Host ""
    
    # Setup environment
    Install-MSYS2
    if (!(Test-Environment)) {
        Write-Error "Environment setup failed"
        exit 1
    }
    
    # Create build directory
    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
    
    # Build process
    if (!(Get-LinuxSource)) { exit 1 }
    if (!(Set-KernelConfiguration)) { exit 1 }
    if (!(Build-Kernel)) { exit 1 }
    if (!(New-KernelPackage)) { exit 1 }
    
    Copy-ToUbuntu
    Show-Summary
    
    Write-Host ""
    Write-Host "🎯 Native Windows build completed successfully!" -ForegroundColor Green
    Write-Host "This should be significantly faster than WSL!" -ForegroundColor Yellow
}

# Script entry point
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
