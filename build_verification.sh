#!/bin/bash
# Advanced build verification and testing script for RG35XX_H

source "$(dirname "${BASH_SOURCE[0]}")/lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/bootimg.sh"

# Comprehensive build verification
verify_build_outputs() {
    log_step "Verifying build outputs"
    
    local verification_passed=true
    local issues=()
    
    # Check kernel image
    if [[ -f "$OUTPUT_DIR/zImage-dtb" ]]; then
        local kernel_size=$(stat -c%s "$OUTPUT_DIR/zImage-dtb")
        if [[ $kernel_size -gt 8388608 ]]; then  # 8MB
            log_success "✅ Kernel image: $(numfmt --to=iec $kernel_size)"
        else
            log_warn "⚠️ Kernel image seems small: $(numfmt --to=iec $kernel_size)"
            issues+=("Small kernel image")
        fi
        
        # Verify kernel architecture
        if file "$OUTPUT_DIR/zImage-dtb" | grep -q "ARM aarch64"; then
            log_success "✅ Kernel architecture: ARM64"
        else
            log_error "❌ Kernel not ARM64!"
            verification_passed=false
            issues+=("Wrong kernel architecture")
        fi
    else
        log_error "❌ Kernel image missing: $OUTPUT_DIR/zImage-dtb"
        verification_passed=false
        issues+=("Missing kernel image")
    fi
    
    # Check boot image
    if [[ -f "$OUTPUT_DIR/boot-new.img" ]]; then
        log_info "Verifying boot image..."
        if verify_boot_image_page_size "$OUTPUT_DIR/boot-new.img"; then
            log_success "✅ Boot image page size: 2048 bytes"
        else
            log_error "❌ Boot image has wrong page size!"
            verification_passed=false
            issues+=("Wrong boot image page size")
        fi
        
        local boot_size=$(stat -c%s "$OUTPUT_DIR/boot-new.img")
        log_info "Boot image size: $(numfmt --to=iec $boot_size)"
    else
        log_error "❌ Boot image missing: $OUTPUT_DIR/boot-new.img"
        verification_passed=false
        issues+=("Missing boot image")
    fi
    
    # Check BusyBox
    if [[ -f "$BUILD_DIR/busybox/_install/bin/busybox" ]]; then
        local busybox_info=$(file "$BUILD_DIR/busybox/_install/bin/busybox")
        if echo "$busybox_info" | grep -q "ARM aarch64"; then
            log_success "✅ BusyBox: ARM64 static binary"
        else
            log_warn "⚠️ BusyBox architecture verification failed"
            issues+=("BusyBox architecture issue")
        fi
        
        # Check BusyBox applets
        local applet_count=$("$BUILD_DIR/busybox/_install/bin/busybox" --list 2>/dev/null | wc -l)
        if [[ $applet_count -gt 100 ]]; then
            log_success "✅ BusyBox applets: $applet_count available"
        else
            log_warn "⚠️ BusyBox has few applets: $applet_count"
            issues+=("Limited BusyBox functionality")
        fi
    else
        log_error "❌ BusyBox binary missing"
        verification_passed=false
        issues+=("Missing BusyBox")
    fi
    
    # Check rootfs
    if [[ -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
        local rootfs_size=$(stat -c%s "$OUTPUT_DIR/rootfs.tar.gz")
        log_success "✅ Root filesystem: $(numfmt --to=iec $rootfs_size)"
    else
        log_error "❌ Root filesystem missing: $OUTPUT_DIR/rootfs.tar.gz"
        verification_passed=false
        issues+=("Missing rootfs")
    fi
    
    # Summary
    echo
    if [[ "$verification_passed" == "true" ]]; then
        log_success "🎉 BUILD VERIFICATION PASSED!"
        log_info "All critical components are present and valid"
        return 0
    else
        log_error "❌ BUILD VERIFICATION FAILED!"
        log_error "Issues found:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        return 1
    fi
}

# Performance testing
run_performance_tests() {
    log_step "Running performance tests"
    
    # Test BusyBox performance
    if [[ -f "$BUILD_DIR/busybox/_install/bin/busybox" ]]; then
        log_info "Testing BusyBox performance..."
        local start_time=$(date +%s%N)
        "$BUILD_DIR/busybox/_install/bin/busybox" --help >/dev/null 2>&1
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        log_info "BusyBox startup time: ${duration}ms"
    fi
    
    # Test boot image creation speed
    if [[ -f "$OUTPUT_DIR/zImage-dtb" ]]; then
        log_info "Testing boot image creation speed..."
        local test_boot="/tmp/test-boot.img"
        local start_time=$(date +%s%N)
        create_boot_image_from_components "$OUTPUT_DIR/zImage-dtb" "" "$test_boot" >/dev/null 2>&1
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        log_info "Boot image creation time: ${duration}ms"
        rm -f "$test_boot"
    fi
}

# Generate build report
generate_build_report() {
    local report_file="$OUTPUT_DIR/build_report.txt"
    log_step "Generating build report"
    
    cat > "$report_file" << EOF
RG35XX_H Custom Build Report
============================
Generated: $(date)
Build ID: $(date +%Y%m%d_%H%M%S)

SYSTEM INFORMATION
------------------
Host: $(hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
Kernel: $(uname -r)
CPU: $(nproc) cores
Memory: $(free -h | grep Mem | awk '{print $2}')

BUILD CONFIGURATION
-------------------
Target Device: RG35XX_H
Kernel Version: $LINUX_BRANCH
BusyBox Version: $BUSYBOX_VERSION
Cross Compiler: $CROSS_COMPILE
Build Jobs: $BUILD_JOBS
DTB Variant: ${DTB_VARIANTS[$DTB_INDEX]}
Package Mode: $PACKAGE_MODE

BUILD OUTPUTS
-------------
EOF

    # Add file information
    if [[ -f "$OUTPUT_DIR/zImage-dtb" ]]; then
        echo "Kernel Image: $(stat -c%s "$OUTPUT_DIR/zImage-dtb" | numfmt --to=iec) ($(stat -c%Y "$OUTPUT_DIR/zImage-dtb" | date -d @- '+%Y-%m-%d %H:%M:%S'))" >> "$report_file"
    fi
    
    if [[ -f "$OUTPUT_DIR/boot-new.img" ]]; then
        echo "Boot Image: $(stat -c%s "$OUTPUT_DIR/boot-new.img" | numfmt --to=iec) ($(stat -c%Y "$OUTPUT_DIR/boot-new.img" | date -d @- '+%Y-%m-%d %H:%M:%S'))" >> "$report_file"
    fi
    
    if [[ -f "$OUTPUT_DIR/rootfs.tar.gz" ]]; then
        echo "Root FS: $(stat -c%s "$OUTPUT_DIR/rootfs.tar.gz" | numfmt --to=iec) ($(stat -c%Y "$OUTPUT_DIR/rootfs.tar.gz" | date -d @- '+%Y-%m-%d %H:%M:%S'))" >> "$report_file"
    fi
    
    # Add verification results
    echo "" >> "$report_file"
    echo "VERIFICATION STATUS" >> "$report_file"
    echo "-------------------" >> "$report_file"
    
    if verify_build_outputs >/dev/null 2>&1; then
        echo "Status: ✅ PASSED" >> "$report_file"
    else
        echo "Status: ❌ FAILED" >> "$report_file"
    fi
    
    log_success "Build report saved: $report_file"
}

# Main verification function
main() {
    case "${1:-verify}" in
        verify)
            verify_build_outputs
            ;;
        performance)
            run_performance_tests
            ;;
        report)
            generate_build_report
            ;;
        all)
            verify_build_outputs
            run_performance_tests
            generate_build_report
            ;;
        help)
            echo "RG35XX_H Build Verification Tool"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  verify      Verify build outputs (default)"
            echo "  performance Run performance tests"
            echo "  report      Generate build report"
            echo "  all         Run all tests and generate report"
            echo "  help        Show this help"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
