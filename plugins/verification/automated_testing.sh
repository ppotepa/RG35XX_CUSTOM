#!/bin/bash
# Automated testing and CI/CD pipeline for RG35XX_H builds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/logger.sh"
source "$SCRIPT_DIR/config/constants.sh"

# Test configuration
TEST_RESULTS_DIR="$SCRIPT_DIR/test_results"
TEST_LOG="$TEST_RESULTS_DIR/test_$(date +%Y%m%d_%H%M%S).log"

# Initialize test environment
init_test_environment() {
    mkdir -p "$TEST_RESULTS_DIR"
    exec 1> >(tee -a "$TEST_LOG")
    exec 2> >(tee -a "$TEST_LOG" >&2)
    
    log_info "=== RG35XX_H Automated Test Suite ==="
    log_info "Started: $(date)"
    log_info "Test log: $TEST_LOG"
    echo
}

# Test individual components
test_cross_compiler() {
    log_step "Testing cross-compiler"
    
    if command -v "$CROSS_COMPILE"gcc >/dev/null 2>&1; then
        local version=$("$CROSS_COMPILE"gcc --version | head -1)
        log_success "✅ Cross-compiler available: $version"
        
        # Test compilation
        local test_c="/tmp/test_compile.c"
        cat > "$test_c" << 'EOF'
#include <stdio.h>
int main() { printf("Hello RG35XX_H\n"); return 0; }
EOF
        
        if "$CROSS_COMPILE"gcc -static -o /tmp/test_binary "$test_c" 2>/dev/null; then
            log_success "✅ Cross-compilation test passed"
            rm -f /tmp/test_binary "$test_c"
            return 0
        else
            log_error "❌ Cross-compilation test failed"
            rm -f "$test_c"
            return 1
        fi
    else
        log_error "❌ Cross-compiler not found: ${CROSS_COMPILE}gcc"
        return 1
    fi
}

test_build_tools() {
    log_step "Testing build tools"
    
    local tools=("make" "git" "dtc" "bc" "bison" "flex")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "✅ $tool available"
        else
            log_error "❌ $tool missing"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "✅ All build tools available"
        return 0
    else
        log_error "❌ Missing tools: ${missing_tools[*]}"
        return 1
    fi
}

test_boot_image_tools() {
    log_step "Testing boot image tools"
    
    local boot_tools=("mkbootimg" "abootimg")
    local available_tools=()
    
    for tool in "${boot_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "✅ $tool available"
            available_tools+=("$tool")
        else
            log_warn "⚠️ $tool not available"
        fi
    done
    
    if [[ ${#available_tools[@]} -gt 0 ]]; then
        log_success "✅ Boot image tools available: ${available_tools[*]}"
        return 0
    else
        log_error "❌ No boot image tools available"
        return 1
    fi
}

# Test kernel configuration
test_kernel_config() {
    log_step "Testing kernel configuration"
    
    if [[ ! -d "$BUILD_DIR/linux" ]]; then
        log_warn "⚠️ Kernel source not available, skipping config test"
        return 0
    fi
    
    cd "$BUILD_DIR/linux"
    
    # Test kernel configuration
    if make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" defconfig >/dev/null 2>&1; then
        log_success "✅ Kernel defconfig generation successful"
    else
        log_error "❌ Kernel defconfig generation failed"
        return 1
    fi
    
    # Check critical config options
    local critical_configs=(
        "CONFIG_ARM64=y"
        "CONFIG_MODULES=y"
        "CONFIG_DEVTMPFS=y"
        "CONFIG_EXT4_FS=y"
    )
    
    for config in "${critical_configs[@]}"; do
        if grep -q "^$config" .config 2>/dev/null; then
            log_success "✅ $config"
        else
            log_warn "⚠️ $config not found"
        fi
    done
    
    return 0
}

# Test BusyBox configuration
test_busybox_config() {
    log_step "Testing BusyBox configuration"
    
    if [[ ! -d "$BUILD_DIR/busybox" ]]; then
        log_warn "⚠️ BusyBox source not available, skipping config test"
        return 0
    fi
    
    cd "$BUILD_DIR/busybox"
    
    # Test BusyBox configuration
    if make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" defconfig >/dev/null 2>&1; then
        log_success "✅ BusyBox defconfig generation successful"
        
        # Check if tc is disabled (known issue)
        if grep -q "CONFIG_TC=y" .config 2>/dev/null; then
            log_warn "⚠️ tc utility enabled - may cause build issues"
        else
            log_success "✅ tc utility properly disabled"
        fi
        
        return 0
    else
        log_error "❌ BusyBox defconfig generation failed"
        return 1
    fi
}

# Performance benchmarks
run_performance_benchmarks() {
    log_step "Running performance benchmarks"
    
    # Build speed estimation
    local cores=$(nproc)
    local memory=$(free -g | awk 'NR==2{print $2}')
    
    log_info "System specs: $cores cores, ${memory}GB RAM"
    
    # Estimate build times
    local kernel_time_min=$((60 / cores))
    local busybox_time_min=$((10 / cores))
    local total_time_min=$((kernel_time_min + busybox_time_min + 5))
    
    log_info "Estimated build times:"
    log_info "  Kernel: ~${kernel_time_min} minutes"
    log_info "  BusyBox: ~${busybox_time_min} minutes"
    log_info "  Total: ~${total_time_min} minutes"
    
    # Disk space check
    local available_gb=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_gb -gt 15 ]]; then
        log_success "✅ Sufficient disk space: ${available_gb}GB"
    else
        log_warn "⚠️ Low disk space: ${available_gb}GB (recommend 15GB+)"
    fi
}

# Integration tests
run_integration_tests() {
    log_step "Running integration tests"
    
    # Test build script syntax
    if bash -n "$SCRIPT_DIR/build.sh" 2>/dev/null; then
        log_success "✅ Main build script syntax OK"
    else
        log_error "❌ Main build script syntax error"
        return 1
    fi
    
    # Test library scripts
    for lib_script in "$SCRIPT_DIR/lib"/*.sh; do
        if [[ -f "$lib_script" ]]; then
            if bash -n "$lib_script" 2>/dev/null; then
                log_success "✅ $(basename "$lib_script") syntax OK"
            else
                log_error "❌ $(basename "$lib_script") syntax error"
                return 1
            fi
        fi
    done
    
    # Test builder scripts
    for builder_script in "$SCRIPT_DIR/builders"/*.sh; do
        if [[ -f "$builder_script" ]]; then
            if bash -n "$builder_script" 2>/dev/null; then
                log_success "✅ $(basename "$builder_script") syntax OK"
            else
                log_error "❌ $(basename "$builder_script") syntax error"
                return 1
            fi
        fi
    done
    
    return 0
}

# Generate test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/test_report_$(date +%Y%m%d_%H%M%S).html"
    
    log_step "Generating test report"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>RG35XX_H Build System Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        .test-section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>RG35XX_H Build System Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Host: $(hostname)</p>
        <p>User: $(whoami)</p>
    </div>
    
    <div class="test-section">
        <h2>Test Summary</h2>
        <p>Log file: <code>$TEST_LOG</code></p>
        <p>Full test output available in log file.</p>
    </div>
    
    <div class="test-section">
        <h2>System Information</h2>
        <pre>$(uname -a)</pre>
        <pre>$(lsb_release -a 2>/dev/null || echo "Distribution: Unknown")</pre>
    </div>
    
    <div class="test-section">
        <h2>Build Environment</h2>
        <pre>Cross Compiler: $CROSS_COMPILE
Target Device: RG35XX_H
Kernel Branch: $LINUX_BRANCH
BusyBox Version: $BUSYBOX_VERSION
Build Jobs: $BUILD_JOBS</pre>
    </div>
</body>
</html>
EOF
    
    log_success "Test report generated: $report_file"
}

# Main test runner
main() {
    local test_suite="${1:-all}"
    local exit_code=0
    
    init_test_environment
    
    case "$test_suite" in
        quick)
            test_cross_compiler || exit_code=1
            test_build_tools || exit_code=1
            test_boot_image_tools || exit_code=1
            ;;
        full)
            test_cross_compiler || exit_code=1
            test_build_tools || exit_code=1
            test_boot_image_tools || exit_code=1
            test_kernel_config || exit_code=1
            test_busybox_config || exit_code=1
            run_integration_tests || exit_code=1
            ;;
        performance)
            run_performance_benchmarks
            ;;
        all)
            test_cross_compiler || exit_code=1
            test_build_tools || exit_code=1
            test_boot_image_tools || exit_code=1
            test_kernel_config || exit_code=1
            test_busybox_config || exit_code=1
            run_performance_benchmarks
            run_integration_tests || exit_code=1
            ;;
        help)
            cat << 'EOF'
RG35XX_H Automated Test Suite

Usage: $0 [test_suite]

Test Suites:
  quick       Quick tests (cross-compiler, tools, boot tools)
  full        Full tests (includes config tests and integration)
  performance Performance benchmarks and estimates
  all         All tests and benchmarks (default)
  help        Show this help

Examples:
  $0              # Run all tests
  $0 quick        # Run quick tests only
  $0 performance  # Run performance tests only
EOF
            exit 0
            ;;
        *)
            log_error "Unknown test suite: $test_suite"
            exit 1
            ;;
    esac
    
    generate_test_report
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        log_success "🎉 ALL TESTS PASSED!"
        log_info "Build environment ready for RG35XX_H development"
    else
        log_error "❌ SOME TESTS FAILED!"
        log_error "Check test log for details: $TEST_LOG"
    fi
    
    log_info "Test completed: $(date)"
    exit $exit_code
}

main "$@"

