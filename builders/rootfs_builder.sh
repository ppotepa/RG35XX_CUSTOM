#!/bin/bash
# Root filesystem creation

source "$(dirname "${BASH_SOURCE[0]}")/../lib/logger.sh"

create_rootfs() {
    log_step "Creating root filesystem"
    start_progress "rootfs" 100
    cd "$BUILD_DIR/rootfs"
    
    update_progress 20 "Creating directory structure..."
    create_directory_structure
    
    update_progress 40 "Creating init script..."
    create_init_script
    
    update_progress 60 "Creating system files..."
    create_system_files
    
    update_progress 80 "Creating rootfs tarball..."
    # Create the rootfs archive with compression
    tar -czf "$OUTPUT_DIR/rootfs.tar.gz" . 2>/dev/null
    
    local size=$(stat -c%s "$OUTPUT_DIR/rootfs.tar.gz" | numfmt --to=iec)
    update_progress 100 "Root filesystem complete"
    end_progress "Root filesystem created ($size)"
    log_success "Root filesystem created ($size)"
}

create_directory_structure() {
    mkdir -p {dev,proc,sys,tmp,mnt,etc,var,run}
}

create_init_script() {
    cat > init << 'EOF'
#!/bin/sh
# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Configure framebuffer console
echo 0 > /sys/class/graphics/fbcon/cursor_blink 2>/dev/null || true

# Find the primary framebuffer
for fb in /sys/class/graphics/fb*; do
    if [ -e "$fb" ]; then
        echo "Found framebuffer: $fb"
        # Enable this framebuffer
        echo 0 > $fb/blank 2>/dev/null || true
        # Set reasonable resolution if needed
        echo "U:1024x600p-60" > $fb/mode 2>/dev/null || true
    fi
done

# Ensure correct console is active
for con in /sys/class/vtconsole/vtcon*; do
    if grep -q "frame buffer" $con/name 2>/dev/null; then
        echo 1 > $con/bind
        echo "Activated framebuffer console: $con"
    fi
done

# Clear screen and display welcome message
clear
echo "====================================="
echo "       RG35HAXX Custom Linux         "
echo "====================================="
echo "System ready. Starting shell..."
exec /bin/sh
EOF
    chmod +x init
}

create_system_files() {
    echo "root:x:0:0:root:/root:/bin/sh" > etc/passwd
    echo "root:x:0:" > etc/group
    echo "RG35HAXX" > etc/hostname
    
    setup_console_files
}

setup_console_files() {
    # Create terminfo directory and basic terminal setup
    mkdir -p etc/terminfo/l
    
    # ASCII art boot logo for console
    cat > etc/issue << 'EOF'
 ____   _____ ____  _____ _    _          __   ____  __
|  _ \ / ____|___ \| ____| |  | |   /\    \ \ / /\ \/ /
| |_) | |  __  __) | |__ | |__| |  /  \    \ V /  \  / 
|  _ <| | |_ |/ __/|___ \|  __  | / /\ \    > <   /  \ 
| |_) | |__| | |__  ___) | |  | |/ ____ \  / . \ / /\ \
|____/ \_____|_____|____/|_|  |_/_/    \_\/_/ \_\/_/  \_\
                                                        
Custom Linux by RG35HAXX Team

EOF

    # Basic terminal settings
    cat > etc/profile << 'EOF'
# Basic environment setup
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export TERM=linux
export PS1='\[\033[01;32m\]\u@rg35haxx\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Enable color support
if [ -x /bin/dircolors ]; then
    eval "$(dircolors -b)"
    alias ls='ls --color=auto'
fi

echo "Welcome to RG35HAXX Custom Linux!"
EOF
}
