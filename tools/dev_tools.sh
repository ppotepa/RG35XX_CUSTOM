#!/bin/bash
# Development utilities and helper tools for RG35XX_H

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

# Quick development commands
dev_clean() {
    log_step "Cleaning development environment"
    
    # Clean build directories but preserve source
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "Cleaning build artifacts..."
        find "$BUILD_DIR" -name "*.o" -o -name "*.ko" -o -name ".tmp_*" | xargs rm -f 2>/dev/null || true
        
        # Clean kernel build artifacts
        if [[ -d "$BUILD_DIR/linux" ]]; then
            cd "$BUILD_DIR/linux"
            make clean >/dev/null 2>&1 || true
            rm -f .config .config.old 2>/dev/null || true
        fi
        
        # Clean BusyBox build artifacts
        if [[ -d "$BUILD_DIR/busybox" ]]; then
            cd "$BUILD_DIR/busybox"
            make clean >/dev/null 2>&1 || true
            rm -rf _install 2>/dev/null || true
        fi
        
        log_success "Build artifacts cleaned"
    fi
    
    # Clean temporary files
    log_info "Cleaning temporary files..."
    rm -rf /tmp/rg35*_* /tmp/test_* /tmp/ssh-control-socket-* 2>/dev/null || true
    
    log_success "Development environment cleaned"
}

dev_status() {
    log_step "Development environment status"
    
    echo "=== Source Status ==="
    if [[ -d "$BUILD_DIR/linux" ]]; then
        cd "$BUILD_DIR/linux"
        local kernel_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        local kernel_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        log_info "Kernel: $kernel_branch ($kernel_commit)"
    else
        log_warn "Kernel source: Not available"
    fi
    
    if [[ -d "$BUILD_DIR/busybox" ]]; then
        cd "$BUILD_DIR/busybox"
        local busybox_version=$(grep "^VERSION" Makefile 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "unknown")
        log_info "BusyBox: version $busybox_version"
    else
        log_warn "BusyBox source: Not available"
    fi
    
    echo
    echo "=== Build Status ==="
    if [[ -f "$OUTPUT_DIR/zImage-dtb" ]]; then
        local kernel_size=$(stat -c%s "$OUTPUT_DIR/zImage-dtb" | numfmt --to=iec)
        local kernel_date=$(stat -c%Y "$OUTPUT_DIR/zImage-dtb" | date -d @- '+%Y-%m-%d %H:%M:%S')
        log_info "Kernel image: $kernel_size ($kernel_date)"
    else
        log_warn "Kernel image: Not built"
    fi
    
    if [[ -f "$OUTPUT_DIR/boot-new.img" ]]; then
        local boot_size=$(stat -c%s "$OUTPUT_DIR/boot-new.img" | numfmt --to=iec)
        local boot_date=$(stat -c%Y "$OUTPUT_DIR/boot-new.img" | date -d @- '+%Y-%m-%d %H:%M:%S')
        log_info "Boot image: $boot_size ($boot_date)"
    else
        log_warn "Boot image: Not built"
    fi
    
    if [[ -f "$BUILD_DIR/busybox/_install/bin/busybox" ]]; then
        local busybox_size=$(stat -c%s "$BUILD_DIR/busybox/_install/bin/busybox" | numfmt --to=iec)
        log_info "BusyBox binary: $busybox_size"
    else
        log_warn "BusyBox binary: Not built"
    fi
    
    echo
    echo "=== Disk Usage ==="
    if [[ -d "$BUILD_DIR" ]]; then
        local build_size=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)
        log_info "Build directory: $build_size"
    fi
    
    if [[ -d "$OUTPUT_DIR" ]]; then
        local output_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
        log_info "Output directory: $output_size"
    fi
}

dev_config() {
    log_step "Development configuration"
    
    local config_file="$SCRIPT_DIR/.dev_config"
    
    case "${1:-show}" in
        show)
            if [[ -f "$config_file" ]]; then
                log_info "Current development configuration:"
                cat "$config_file"
            else
                log_info "No custom development configuration found"
                log_info "Using defaults from config/constants.sh"
            fi
            ;;
        edit)
            log_info "Opening configuration for editing..."
            if command -v nano >/dev/null 2>&1; then
                nano "$config_file"
            elif command -v vi >/dev/null 2>&1; then
                vi "$config_file"
            else
                log_error "No text editor available"
                return 1
            fi
            ;;
        reset)
            if [[ -f "$config_file" ]]; then
                rm "$config_file"
                log_success "Development configuration reset to defaults"
            else
                log_info "No custom configuration to reset"
            fi
            ;;
    esac
}

dev_kernel_modules() {
    log_step "Kernel modules development tools"
    
    case "${1:-list}" in
        list)
            if [[ -d "$BUILD_DIR/linux" ]]; then
                cd "$BUILD_DIR/linux"
                log_info "Available kernel modules:"
                find . -name "*.ko" 2>/dev/null | head -20 || log_info "No compiled modules found"
            else
                log_warn "Kernel source not available"
            fi
            ;;
        config)
            if [[ -d "$BUILD_DIR/linux" ]]; then
                cd "$BUILD_DIR/linux"
                log_info "Opening kernel module configuration..."
                make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" menuconfig
            else
                log_error "Kernel source not available"
                return 1
            fi
            ;;
        build)
            log_info "Building specific kernel module: $2"
            if [[ -d "$BUILD_DIR/linux" && -n "$2" ]]; then
                cd "$BUILD_DIR/linux"
                make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" "$2"
            else
                log_error "Usage: dev_kernel_modules build <module_name>"
                return 1
            fi
            ;;
    esac
}

dev_debug() {
    log_step "Debug information collection"
    
    local debug_file="$SCRIPT_DIR/debug_info_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "RG35XX_H Debug Information"
        echo "=========================="
        echo "Generated: $(date)"
        echo "Host: $(hostname)"
        echo "User: $(whoami)"
        echo
        
        echo "=== System Information ==="
        uname -a
        echo
        lsb_release -a 2>/dev/null || echo "Distribution: Unknown"
        echo
        
        echo "=== Environment Variables ==="
        env | grep -E "(CROSS_COMPILE|BUILD_DIR|OUTPUT_DIR|PATH)" | sort
        echo
        
        echo "=== Tool Versions ==="
        echo "GCC: $(gcc --version 2>/dev/null | head -1 || echo "Not available")"
        echo "Cross GCC: $($CROSS_COMPILE"gcc" --version 2>/dev/null | head -1 || echo "Not available")"
        echo "Make: $(make --version 2>/dev/null | head -1 || echo "Not available")"
        echo "Git: $(git --version 2>/dev/null || echo "Not available")"
        echo
        
        echo "=== Build Status ==="
        if [[ -d "$BUILD_DIR" ]]; then
            find "$BUILD_DIR" -maxdepth 2 -type d | sort
        else
            echo "Build directory not found"
        fi
        echo
        
        echo "=== Recent Logs ==="
        if [[ -d "$SCRIPT_DIR/logs" ]]; then
            ls -la "$SCRIPT_DIR/logs" | tail -10
        else
            echo "No log directory found"
        fi
        
    } > "$debug_file"
    
    log_success "Debug information saved: $debug_file"
}

dev_benchmark() {
    log_step "Development benchmark"
    
    log_info "Running development environment benchmarks..."
    
    # CPU benchmark
    log_info "CPU benchmark (compiling test program)..."
    local test_c="/tmp/benchmark_test.c"
    cat > "$test_c" << 'EOF'
#include <stdio.h>
#include <math.h>
int main() {
    double result = 0;
    for (int i = 0; i < 1000000; i++) {
        result += sin(i) * cos(i);
    }
    printf("Result: %f\n", result);
    return 0;
}
EOF
    
    local start_time=$(date +%s%N)
    gcc -O2 -lm -o /tmp/benchmark_binary "$test_c" 2>/dev/null
    local end_time=$(date +%s%N)
    local compile_time=$(( (end_time - start_time) / 1000000 ))
    log_info "Compilation time: ${compile_time}ms"
    
    # Cross-compilation benchmark
    if command -v "$CROSS_COMPILE"gcc >/dev/null 2>&1; then
        start_time=$(date +%s%N)
        "$CROSS_COMPILE"gcc -static -O2 -lm -o /tmp/benchmark_cross "$test_c" 2>/dev/null
        end_time=$(date +%s%N)
        local cross_compile_time=$(( (end_time - start_time) / 1000000 ))
        log_info "Cross-compilation time: ${cross_compile_time}ms"
    fi
    
    # Disk I/O benchmark
    log_info "Disk I/O benchmark..."
    start_time=$(date +%s%N)
    dd if=/dev/zero of=/tmp/benchmark_io bs=1M count=100 2>/dev/null
    end_time=$(date +%s%N)
    local io_time=$(( (end_time - start_time) / 1000000 ))
    log_info "Disk write time (100MB): ${io_time}ms"
    
    # Cleanup
    rm -f /tmp/benchmark_* "$test_c" 2>/dev/null
    
    log_success "Benchmark complete"
}

# Main function
main() {
    case "${1:-help}" in
        clean)
            dev_clean
            ;;
        status)
            dev_status
            ;;
        config)
            dev_config "${2:-show}"
            ;;
        modules)
            dev_kernel_modules "${2:-list}" "$3"
            ;;
        debug)
            dev_debug
            ;;
        benchmark)
            dev_benchmark
            ;;
        help)
            cat << 'EOF'
RG35XX_H Development Utilities

Usage: $0 <command> [options]

Commands:
  clean               Clean build artifacts and temporary files
  status              Show development environment status
  config [show|edit|reset]  Manage development configuration
  modules [list|config|build] Kernel modules development tools
  debug               Collect debug information
  benchmark           Run development environment benchmarks
  help                Show this help

Examples:
  $0 status           # Show current status
  $0 clean            # Clean build artifacts
  $0 config edit      # Edit development configuration
  $0 modules config   # Configure kernel modules
  $0 debug            # Collect debug info for troubleshooting
EOF
            ;;
        *)
            log_error "Unknown command: $1"
            log_error "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"

