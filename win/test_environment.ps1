#!/usr/bin/env pwsh
# Quick test script for the Windows kernel builder

param (
    [switch]$DryRun = $false
)

Write-Host "🧪 Testing RG35XX_H Windows Kernel Builder" -ForegroundColor Magenta

# Test WSL availability
Write-Host "Testing WSL..." -ForegroundColor Yellow
try {
    wsl --version 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ WSL is available" -ForegroundColor Green
    } else {
        Write-Host "❌ WSL not available" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ WSL test failed: $_" -ForegroundColor Red
    exit 1
}

# Test Ubuntu distribution
Write-Host "Testing Ubuntu distribution..." -ForegroundColor Yellow
$distros = wsl --list --quiet
if ($distros -contains "Ubuntu") {
    Write-Host "✅ Ubuntu distribution found" -ForegroundColor Green
} else {
    Write-Host "❌ Ubuntu distribution not found" -ForegroundColor Red
    Write-Host "Install with: wsl --install -d Ubuntu" -ForegroundColor Yellow
    exit 1
}

# Test basic build tools in WSL
Write-Host "Testing build tools in WSL..." -ForegroundColor Yellow
$toolsTest = @'
#!/bin/bash
echo "Testing basic tools..."
command -v gcc >/dev/null 2>&1 || { echo "gcc not found"; exit 1; }
command -v make >/dev/null 2>&1 || { echo "make not found"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git not found"; exit 1; }
echo "Basic tools OK"
'@

$toolsTest | wsl bash
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Basic build tools available" -ForegroundColor Green
} else {
    Write-Host "⚠️  Some build tools missing (will be installed automatically)" -ForegroundColor Yellow
}

# Test cross-compiler
Write-Host "Testing cross-compiler..." -ForegroundColor Yellow
$crossTest = "command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 && echo 'Cross-compiler OK' || echo 'Cross-compiler missing'"
$crossResult = $crossTest | wsl bash
if ($crossResult -match "OK") {
    Write-Host "✅ Cross-compiler available" -ForegroundColor Green
} else {
    Write-Host "⚠️  Cross-compiler missing (will be installed automatically)" -ForegroundColor Yellow
}

# Test SSH connectivity (if not dry run)
if (!$DryRun) {
    Write-Host "Testing SSH connectivity..." -ForegroundColor Yellow
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@192.168.100.26 "echo 'SSH connection OK'" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ SSH connection to Ubuntu machine works" -ForegroundColor Green
    } else {
        Write-Host "⚠️  SSH connection failed (check network/credentials)" -ForegroundColor Yellow
        Write-Host "Target: root@192.168.100.26" -ForegroundColor Gray
    }
}

# Test config_patch file
Write-Host "Testing config_patch..." -ForegroundColor Yellow
$configPath = "../config_patch"
if (Test-Path $configPath) {
    $configLines = (Get-Content $configPath | Measure-Object -Line).Lines
    Write-Host "✅ config_patch found ($configLines lines)" -ForegroundColor Green
} else {
    Write-Host "❌ config_patch not found at $configPath" -ForegroundColor Red
    exit 1
}

# Test PowerShell version
Write-Host "Testing PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 5) {
    Write-Host "✅ PowerShell $psVersion (compatible)" -ForegroundColor Green
} else {
    Write-Host "⚠️  PowerShell $psVersion (may have compatibility issues)" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "🎯 Test Summary" -ForegroundColor Cyan
Write-Host "✅ System appears ready for kernel building" -ForegroundColor Green
Write-Host ""
Write-Host "To start building:" -ForegroundColor Yellow
Write-Host "  .\build_kernel_win.ps1" -ForegroundColor White
Write-Host ""
Write-Host "For first run with debug:" -ForegroundColor Yellow  
Write-Host "  .\build_kernel_win.ps1 -ForceRebuild -DebugCmdline" -ForegroundColor White
