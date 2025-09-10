#!/usr/bin/env pwsh
# Quick test for native Windows kernel build environment

param (
    [switch]$InstallMsys2 = $false
)

$ErrorActionPreference = "Stop"

# MSYS2 paths
$MSYS2_ROOT = "C:\msys64"
$MSYS2_BIN = "$MSYS2_ROOT\usr\bin"
$MINGW64_BIN = "$MSYS2_ROOT\mingw64\bin"

function Write-TestResult {
    param($Test, $Result, $Details = "")
    if ($Result) {
        Write-Host "✅ $Test" -ForegroundColor Green
        if ($Details) { Write-Host "   $Details" -ForegroundColor Gray }
    } else {
        Write-Host "❌ $Test" -ForegroundColor Red
        if ($Details) { Write-Host "   $Details" -ForegroundColor Yellow }
    }
}

Write-Host "🧪 Testing Native Windows Build Environment" -ForegroundColor Magenta
Write-Host ""

# Test 1: MSYS2 Installation
$msys2Installed = Test-Path "$MSYS2_BIN\bash.exe"
Write-TestResult "MSYS2 Installation" $msys2Installed "Found at $MSYS2_ROOT"

if (!$msys2Installed -and $InstallMsys2) {
    Write-Host ""
    Write-Host "📥 Installing MSYS2..." -ForegroundColor Yellow
    
    try {
        $msys2Installer = "$env:TEMP\msys2-x86_64-latest.exe"
        Write-Host "Downloading MSYS2 installer..." -ForegroundColor Gray
        
        Invoke-WebRequest -Uri "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe" -OutFile $msys2Installer -UseBasicParsing
        
        Write-Host "Installing MSYS2..." -ForegroundColor Gray
        Start-Process -FilePath $msys2Installer -ArgumentList "--confirm-command", "--accept-messages", "--root", "C:\msys64" -Wait
        
        Remove-Item $msys2Installer -Force
        
        $msys2Installed = Test-Path "$MSYS2_BIN\bash.exe"
        Write-TestResult "MSYS2 Installation" $msys2Installed "Installed successfully"
    } catch {
        Write-Host "❌ Failed to install MSYS2: $_" -ForegroundColor Red
    }
}

if (!$msys2Installed) {
    Write-Host ""
    Write-Host "To install MSYS2:" -ForegroundColor Yellow
    Write-Host "  .\test_native.ps1 -InstallMsys2" -ForegroundColor White
    Write-Host "Or download manually from: https://www.msys2.org/" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Test 2: Basic Tools
$env:PATH = "$MINGW64_BIN;$MSYS2_BIN;$env:PATH"

$bashWorks = $false
try {
    $bashTest = & "$MSYS2_BIN\bash.exe" -c "echo 'bash works'" 2>$null
    $bashWorks = $bashTest -eq "bash works"
} catch {}
Write-TestResult "MSYS2 Bash" $bashWorks

$gitWorks = $false
try {
    $gitTest = & "$MSYS2_BIN\bash.exe" -c "git --version" 2>$null
    $gitWorks = $gitTest -match "git version"
} catch {}
Write-TestResult "Git" $gitWorks "$gitTest"

$makeWorks = $false
try {
    $makeTest = & "$MSYS2_BIN\bash.exe" -c "make --version" 2>$null | Select-Object -First 1
    $makeWorks = $makeTest -match "GNU Make"
} catch {}
Write-TestResult "Make" $makeWorks "$makeTest"

# Test 3: Cross-compiler options
Write-Host ""
Write-Host "🔍 Checking for ARM64 cross-compilers..." -ForegroundColor Cyan

# Option 1: Check for aarch64-none-linux-gnu (preferred)
$toolchain1 = "$MSYS2_ROOT\opt\aarch64-none-linux-gnu\bin\aarch64-none-linux-gnu-gcc.exe"
$gcc1Works = Test-Path $toolchain1
Write-TestResult "ARM Embedded Toolchain" $gcc1Works "aarch64-none-linux-gnu-gcc"

# Option 2: Check for mingw version
$gcc2Works = $false
try {
    $gcc2Test = & "$MSYS2_BIN\bash.exe" -c "pacman -Q mingw-w64-x86_64-aarch64-elf-gcc" 2>$null
    $gcc2Works = $gcc2Test -match "mingw-w64-x86_64-aarch64-elf-gcc"
} catch {}
Write-TestResult "MSYS2 AArch64 GCC" $gcc2Works "via pacman"

# Test 4: Performance estimation
Write-Host ""
Write-Host "💻 System Performance" -ForegroundColor Cyan
$cores = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
$memory = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Host "  CPU Cores: $cores" -ForegroundColor White
Write-Host "  RAM: ${memory} GB" -ForegroundColor White
Write-Host "  Estimated kernel build time: $([math]::Max(2, 10 - $cores)) minutes" -ForegroundColor Gray

# Test 5: SSH for remote copy
$sshWorks = $false
try {
    $sshTest = & ssh -V 2>&1 | Select-Object -First 1
    $sshWorks = $sshTest -match "OpenSSH"
} catch {}
Write-TestResult "SSH Client" $sshWorks "For copying to Ubuntu"

# Summary
Write-Host ""
Write-Host "📊 Environment Summary" -ForegroundColor Cyan

$readyForBuild = $msys2Installed -and $bashWorks -and $gitWorks -and $makeWorks -and ($gcc1Works -or $gcc2Works)

if ($readyForBuild) {
    Write-Host "✅ Environment ready for native Windows kernel builds!" -ForegroundColor Green
    Write-Host ""
    Write-Host "To build kernel:" -ForegroundColor Yellow
    Write-Host "  .\build_kernel_native.ps1 -DebugCmdline" -ForegroundColor White
    Write-Host ""
    Write-Host "Expected performance improvement over WSL:" -ForegroundColor Cyan
    Write-Host "  🚀 2-4x faster compilation" -ForegroundColor White
    Write-Host "  💾 No filesystem translation overhead" -ForegroundColor White
    Write-Host "  ⚡ Direct Windows I/O performance" -ForegroundColor White
} else {
    Write-Host "⚠️  Environment needs setup" -ForegroundColor Yellow
    Write-Host ""
    if (!$gcc1Works -and !$gcc2Works) {
        Write-Host "Missing cross-compiler. The build script will install it automatically." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Performance comparison:" -ForegroundColor Gray
Write-Host "  WSL2: ~25% of native Windows speed" -ForegroundColor Red
Write-Host "  Native MSYS2: ~85-95% of native Linux speed" -ForegroundColor Green
