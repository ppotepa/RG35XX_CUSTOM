#!/bin/bash
# BusyBox builder for RG35XX_H Custom Linux Builder

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"

get_busybox_source() {
    log_info "Getting BusyBox source..."
    
    # Check if BusyBox directory exists and has a valid Makefile
    if [[ -d "$BUILD_DIR/busybox" ]] && [[ -f "$BUILD_DIR/busybox/Makefile" ]]; then
        log_info "Using existing BusyBox source at $BUILD_DIR/busybox"
        return 0
    fi
    
    # Remove invalid/incomplete directory if it exists
    if [[ -d "$BUILD_DIR/busybox" ]]; then
        log_warn "Removing incomplete BusyBox directory"
        rm -rf "$BUILD_DIR/busybox"
    fi
    
    log_info "Downloading BusyBox $BUSYBOX_VERSION..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    wget -q "$BUSYBOX_URL" -O "busybox-${BUSYBOX_VERSION}.tar.bz2" || {
        log_error "Failed to download BusyBox"
        return 1
    }
    
    tar -xjf "busybox-${BUSYBOX_VERSION}.tar.bz2" || {
        log_error "Failed to extract BusyBox"
        return 1
    }
    
    mv "busybox-${BUSYBOX_VERSION}" busybox
    rm "busybox-${BUSYBOX_VERSION}.tar.bz2"
    
    log_success "BusyBox source downloaded and extracted"
    return 0
}

configure_busybox() {
    log_info "Configuring BusyBox..."
    
    cd "$BUILD_DIR/busybox"
    
    # Start with a minimal configuration to avoid problematic features
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" allnoconfig || {
        log_error "Failed to create minimal BusyBox config"
        return 1
    }
    
    # Apply custom config to enable essential features
    if [[ -f "$SCRIPT_DIR/busybox_config_patch" ]]; then
        log_info "Applying custom BusyBox configuration..."
        cat "$SCRIPT_DIR/busybox_config_patch" >> .config
    fi
    
    # Explicitly enable essential applets
    cat >> .config << 'EOF'
CONFIG_BUSYBOX=y
CONFIG_SHOW_USAGE=y
CONFIG_FEATURE_VERBOSE_USAGE=y
CONFIG_LFS=y
CONFIG_STATIC=y
# CONFIG_TC is not set
# CONFIG_FEATURE_TC_INGRESS is not set
# CONFIG_BRCTL is not set
# CONFIG_VCONFIG is not set
CONFIG_SH_IS_ASH=y
CONFIG_BASH_IS_NONE=y
CONFIG_ASH=y
CONFIG_ASH_BASH_COMPAT=y
CONFIG_ASH_CMDCMD=y
CONFIG_ASH_ECHO=y
CONFIG_ASH_PRINTF=y
CONFIG_ASH_TEST=y
CONFIG_COREUTILS=y
CONFIG_CAT=y
CONFIG_CP=y
CONFIG_DD=y
CONFIG_LS=y
CONFIG_MKDIR=y
CONFIG_MV=y
CONFIG_RM=y
CONFIG_CHMOD=y
CONFIG_CHOWN=y
CONFIG_MOUNT=y
CONFIG_UMOUNT=y
CONFIG_GREP=y
CONFIG_SED=y
CONFIG_TAR=y
CONFIG_GZIP=y
CONFIG_GUNZIP=y
CONFIG_FIND=y
CONFIG_PS=y
CONFIG_TOP=y
CONFIG_FREE=y
CONFIG_KILLALL=y
CONFIG_PING=y
CONFIG_WGET=y
CONFIG_TFTP=y
CONFIG_NETSTAT=y
CONFIG_IFCONFIG=y
CONFIG_ROUTE=y
CONFIG_ARP=y
CONFIG_INIT=y
CONFIG_HALT=y
CONFIG_REBOOT=y
CONFIG_POWEROFF=y
CONFIG_SYSLOGD=y
CONFIG_KLOGD=y
CONFIG_MDEV=y
CONFIG_DEPMOD=y
CONFIG_INSMOD=y
CONFIG_LSMOD=y
CONFIG_MODPROBE=y
CONFIG_RMMOD=y
EOF
    
    # Apply configuration and resolve dependencies without interactive prompts
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" oldconfig < /dev/null
    
    # Final verification that problematic features are disabled
    if grep -q "CONFIG_TC=y" .config; then
        log_warn "TC still enabled, forcing disable..."
        sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config
    fi
    
    if grep -q "CONFIG_BRCTL=y" .config; then
        log_warn "BRCTL enabled, disabling to avoid potential issues..."
        sed -i 's/CONFIG_BRCTL=y/# CONFIG_BRCTL is not set/' .config
    fi
    
    # Final config pass
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" oldconfig < /dev/null
    
    log_info "BusyBox configuration completed"
    return 0
}

build_busybox() {
    log_info "Building BusyBox..."
    
    cd "$BUILD_DIR/busybox"
    
    # Clear any problematic environment variables
    unset CPPFLAGS
    unset LDLIBS
    
    # Use compatible cross-compilation flags for BusyBox
    export CFLAGS="-O2 -march=armv8-a -mtune=cortex-a53 -static"
    export LDFLAGS="-static"
    
    log_info "Building with configuration summary:"
    echo "================================================"
    echo "TC utility: $(grep -q 'CONFIG_TC=y' .config && echo 'ENABLED (ERROR!)' || echo 'DISABLED (OK)')"
    echo "Static build: $(grep -q 'CONFIG_STATIC=y' .config && echo 'ENABLED (OK)' || echo 'DISABLED (ERROR!)')"
    echo "Cross compiler: $CROSS_COMPILE"
    echo "CFLAGS: $CFLAGS"
    echo "LDFLAGS: $LDFLAGS"
    echo "================================================"
    
    # Build BusyBox with verbose output to catch issues early
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" V=1 -j"$BUILD_JOBS" || {
        log_error "Failed to build BusyBox"
        log_error "Checking for problematic configuration..."
        
        if grep -q 'CONFIG_TC=y' .config; then
            log_error "TC utility is still enabled in configuration!"
            return 1
        fi
        
        return 1
    }
    
    log_info "Installing BusyBox..."
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" install || {
        log_error "Failed to install BusyBox"
        return 1
    }
    
    # Verify the built binary
    if [[ -f "_install/bin/busybox" ]]; then
        local bb_info=$(file "_install/bin/busybox")
        log_info "BusyBox binary info: $bb_info"
        
        if echo "$bb_info" | grep -q "ARM aarch64"; then
            log_success "BusyBox built successfully for ARM64"
        else
            log_warn "BusyBox binary might not be built for correct architecture"
        fi
    else
        log_error "BusyBox binary not found after installation"
        return 1
    fi
    
    return 0
}
