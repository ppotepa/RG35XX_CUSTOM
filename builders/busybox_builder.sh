#!/bin/bash
# BusyBox building functionality

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

get_busybox_source() {
    step "Getting BusyBox source"
    
    if [[ ! -f "$SCRIPT_DIR/busybox-$BUSYBOX_VERSION.tar.bz2" ]]; then
        log "Downloading BusyBox..."
        wget -q -O "$SCRIPT_DIR/busybox-$BUSYBOX_VERSION.tar.bz2" \
            "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"
    fi
    
    log "Extracting BusyBox..."
    tar -xf "$SCRIPT_DIR/busybox-$BUSYBOX_VERSION.tar.bz2" -C "$BUILD_DIR/"
    mv "$BUILD_DIR/busybox-$BUSYBOX_VERSION" "$BUILD_DIR/busybox"
}

configure_busybox() {
    cd "$BUILD_DIR/busybox"
    
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" defconfig
    
    apply_busybox_config
    
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" oldconfig
}

apply_busybox_config() {
    if [[ -f "$SCRIPT_DIR/busybox_config_patch" ]]; then
        log "Applying BusyBox configuration..."
        while IFS='=' read -r key val; do
            [[ "$key" =~ ^CONFIG_[A-Z0-9_]+$ ]] || continue
            case "$val" in
                y|Y) scripts/config --enable "$key" ;;
                n|N) scripts/config --disable "$key" ;;
                m|M) scripts/config --module "$key" ;;
            esac
        done < <(sed 's/\r$//' "$SCRIPT_DIR/busybox_config_patch" | grep -E '^CONFIG_')
    else
        # Disable problematic features
        scripts/config --disable CONFIG_TC
        scripts/config --disable CONFIG_FEATURE_IP_ROUTE_VERBOSE
    fi
}

build_busybox() {
    step "Building BusyBox"
    
    configure_busybox
    
    log "Building BusyBox..."
    make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE"
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
         CONFIG_PREFIX="$BUILD_DIR/rootfs" install
}
