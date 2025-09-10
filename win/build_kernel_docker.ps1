#!/usr/bin/env pwsh
# Ultra-fast kernel build using Docker on Windows
# Alternative to MSYS2 - uses containerized Linux environment

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
$BUILD_DIR = "$SCRIPT_DIR\build_docker"
$OUTPUT_DIR = "$BUILD_DIR\output"

# Build configuration
$LINUX_BRANCH = "linux-6.10.y"
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

function Test-Docker {
    Write-Header "Checking Docker environment"
    
    try {
        $dockerVersion = docker --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker found: $dockerVersion"
        } else {
            Write-Error "Docker not found. Please install Docker Desktop"
            Write-Host "Download from: https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
            return $false
        }
        
        # Test if Docker daemon is running
        $dockerInfo = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker daemon is running"
        } else {
            Write-Error "Docker daemon not running. Please start Docker Desktop"
            return $false
        }
        
        return $true
    } catch {
        Write-Error "Docker test failed: $_"
        return $false
    }
}

function Build-KernelInDocker {
    Write-Header "Building kernel in Docker container"
    
    # Create build directory
    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    
    # Copy config patch to build directory
    Copy-Item "$ROOT_DIR\config_patch" "$BUILD_DIR\config_patch" -Force
    
    # Create Dockerfile for kernel build
    $dockerfile = @"
FROM ubuntu:22.04

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git make gcc bc bison flex libssl-dev libelf-dev \
    gcc-aarch64-linux-gnu wget curl tar rsync cpio \
    util-linux e2fsprogs device-tree-compiler \
    build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /build

# Copy config patch
COPY config_patch /build/config_patch

# Build script
RUN echo '#!/bin/bash' > /build/build.sh && \
    echo 'set -e' >> /build/build.sh && \
    echo 'export ARCH=arm64' >> /build/build.sh && \
    echo 'export CROSS_COMPILE=aarch64-linux-gnu-' >> /build/build.sh && \
    echo 'echo "Getting kernel source..."' >> /build/build.sh && \
    echo 'if [ ! -d linux ] || [ "$1" = "force" ]; then' >> /build/build.sh && \
    echo '  rm -rf linux' >> /build/build.sh && \
    echo '  git clone --depth=1 --branch $LINUX_BRANCH https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux' >> /build/build.sh && \
    echo 'fi' >> /build/build.sh && \
    echo 'cd linux' >> /build/build.sh && \
    echo 'echo "Configuring kernel..."' >> /build/build.sh && \
    echo 'make defconfig' >> /build/build.sh && \
    echo 'if [ -f /build/config_patch ]; then' >> /build/build.sh && \
    echo '  ./scripts/kconfig/merge_config.sh -m .config /build/config_patch' >> /build/build.sh && \
    echo 'fi' >> /build/build.sh && \
    echo 'if [ "$2" = "debug" ]; then' >> /build/build.sh && \
    echo '  echo "CONFIG_CMDLINE=\"console=ttyS0,115200 console=tty0 earlycon=uart,mmio32,0x02500000 root=PARTLABEL=rootfs rootfstype=ext4 rootwait init=/init loglevel=7 ignore_loglevel panic=10 initcall_debug\"" >> .config' >> /build/build.sh && \
    echo 'else' >> /build/build.sh && \
    echo '  echo "CONFIG_CMDLINE=\"console=tty0 console=ttyS0,115200 root=PARTLABEL=rootfs rootfstype=ext4 rootwait loglevel=4\"" >> .config' >> /build/build.sh && \
    echo 'fi' >> /build/build.sh && \
    echo 'echo "CONFIG_CMDLINE_BOOL=y" >> .config' >> /build/build.sh && \
    echo 'echo "CONFIG_CMDLINE_FORCE=y" >> .config' >> /build/build.sh && \
    echo 'make olddefconfig' >> /build/build.sh && \
    echo 'echo "Building kernel..."' >> /build/build.sh && \
    echo 'make -j$(nproc) Image dtbs modules' >> /build/build.sh && \
    echo 'echo "Packaging outputs..."' >> /build/build.sh && \
    echo 'mkdir -p /output' >> /build/build.sh && \
    echo 'cp arch/arm64/boot/Image /output/' >> /build/build.sh && \
    echo 'mkdir -p /output/dtbs' >> /build/build.sh && \
    echo 'cp arch/arm64/boot/dts/allwinner/sun50i-h700-*.dtb /output/dtbs/ 2>/dev/null || true' >> /build/build.sh && \
    echo 'DTB_FILES=(${DTB_VARIANTS[@]})' >> /build/build.sh && \
    echo 'DTB_FILE="arch/arm64/boot/dts/allwinner/\${DTB_FILES[$3]}"' >> /build/build.sh && \
    echo 'if [ -f "\$DTB_FILE" ]; then' >> /build/build.sh && \
    echo '  cat arch/arm64/boot/Image "\$DTB_FILE" > /output/zImage-dtb' >> /build/build.sh && \
    echo '  cp "\$DTB_FILE" /output/dtb' >> /build/build.sh && \
    echo 'else' >> /build/build.sh && \
    echo '  FALLBACK=\$(find arch/arm64/boot/dts/allwinner/ -name "sun50i-h700-*.dtb" | head -1)' >> /build/build.sh && \
    echo '  if [ -f "\$FALLBACK" ]; then' >> /build/build.sh && \
    echo '    cat arch/arm64/boot/Image "\$FALLBACK" > /output/zImage-dtb' >> /build/build.sh && \
    echo '    cp "\$FALLBACK" /output/dtb' >> /build/build.sh && \
    echo '  fi' >> /build/build.sh && \
    echo 'fi' >> /build/build.sh && \
    echo 'mkdir -p /tmp/modules' >> /build/build.sh && \
    echo 'make INSTALL_MOD_PATH=/tmp/modules modules_install' >> /build/build.sh && \
    echo 'cd /tmp/modules && tar -czf /output/modules.tar.gz .' >> /build/build.sh && \
    echo 'echo "Kernel: \$(cd /build/linux && make kernelversion)" > /output/kernel_info.txt' >> /build/build.sh && \
    echo 'echo "Build Date: \$(date)" >> /output/kernel_info.txt' >> /build/build.sh && \
    echo 'echo "Build Method: Docker Container" >> /output/kernel_info.txt' >> /build/build.sh && \
    chmod +x /build/build.sh

CMD ["/build/build.sh"]
"@

    $dockerfile | Out-File -FilePath "$BUILD_DIR\Dockerfile" -Encoding UTF8
    
    # Build Docker image
    Write-Host "Building Docker image..." -ForegroundColor Yellow
    docker build -t rg35xx-kernel-builder "$BUILD_DIR"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build Docker image"
        return $false
    }
    
    # Run kernel build in container
    Write-Host "Running kernel build in container..." -ForegroundColor Yellow
    $cores = [Environment]::ProcessorCount
    Write-Host "Using $cores CPU cores for parallel build" -ForegroundColor Gray
    
    $forceFlag = if ($ForceRebuild) { "force" } else { "" }
    $debugFlag = if ($DebugCmdline) { "debug" } else { "" }
    $dtbIndex = [int]$DtbVariant
    
    $startTime = Get-Date
    docker run --rm --cpus="$cores" -v "${OUTPUT_DIR}:/output" rg35xx-kernel-builder /build/build.sh $forceFlag $debugFlag $dtbIndex
    $endTime = Get-Date
    $buildTime = ($endTime - $startTime).TotalMinutes
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Kernel build failed in container"
        return $false
    }
    
    Write-Success "Kernel built successfully in $($buildTime.ToString("F1")) minutes"
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
        
        # Copy all outputs
        & scp "$OUTPUT_DIR\*" "${RemoteHost}:${RemotePath}/build/"
        
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
    Write-Header "Docker Build Summary"
    
    Write-Host "🐳 Docker-based kernel build completed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Performance benefits:" -ForegroundColor Cyan
    Write-Host "  🚀 Native Linux compilation in container" -ForegroundColor White
    Write-Host "  💨 Full CPU utilization ($([Environment]::ProcessorCount) cores)" -ForegroundColor White
    Write-Host "  🔄 Faster than WSL2 (no translation layer)" -ForegroundColor White
    Write-Host "  📦 Clean, reproducible build environment" -ForegroundColor White
    
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
    Write-Host "🐳 RG35XX_H Docker Kernel Builder" -ForegroundColor Magenta
    Write-Host "Fast kernel compilation using Docker containers" -ForegroundColor Gray
    Write-Host ""
    
    if (!(Test-Docker)) {
        Write-Host ""
        Write-Host "Docker alternatives:" -ForegroundColor Yellow
        Write-Host "  1. Use .\build_kernel_native.ps1 (MSYS2)" -ForegroundColor White
        Write-Host "  2. Install Docker Desktop and try again" -ForegroundColor White
        exit 1
    }
    
    if (!(Build-KernelInDocker)) {
        exit 1
    }
    
    Copy-ToUbuntu
    Show-Summary
    
    Write-Host ""
    Write-Host "🎯 Docker build completed successfully!" -ForegroundColor Green
}

# Script entry point
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
