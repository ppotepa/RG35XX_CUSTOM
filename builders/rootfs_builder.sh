#!/bin/bash
# Root filesystem creation

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"

create_rootfs() {
    step "Creating root filesystem"
    cd "$BUILD_DIR/rootfs"
    
    create_directory_structure
    create_init_script
    create_system_files
    
    log "Root filesystem created"
}

create_directory_structure() {
    mkdir -p {dev,proc,sys,tmp,mnt,etc,var,run}
}

create_init_script() {
    cat > init << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
echo "=== RG35XX_H Custom Linux ==="
echo "System ready. Starting shell..."
exec /bin/sh
EOF
    chmod +x init
}

create_system_files() {
    echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
    echo "root:x:0:" > etc/group
    echo "RG35XX_H Custom Linux" > etc/hostname
}
