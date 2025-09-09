#!/bin/bash
# Test script for progress tracking functionality

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# Source logger with progress functions
source "$SCRIPT_DIR/lib/logger.sh"

echo "Testing RG35HAXX Progress Tracking System"
echo "=========================================="

# Test kernel build simulation
echo "Simulating kernel build..."
start_progress "kernel" 100
for i in {1..100}; do
    update_progress $i "Building kernel... ($i%)"
    sleep 0.02
done
end_progress "Kernel build complete"

echo ""

# Test busybox build simulation
echo "Simulating BusyBox build..."
start_progress "busybox" 100
for i in {1..100}; do
    update_progress $i "Building BusyBox... ($i%)"
    sleep 0.01
done
end_progress "BusyBox build complete"

echo ""

# Test overall progress with dual bars
echo "Testing dual progress bars..."
sleep 1

# Simulate overall build process
start_progress "overall" 100

# Phase 1: Kernel (40% of total)
update_progress 5 "Starting kernel build..."
start_progress "kernel" 100
for i in {1..100}; do
    update_progress $i "Building kernel..."
    # Update overall progress proportionally
    overall_progress=$((5 + (i * 35 / 100)))
    update_progress $overall_progress "Kernel build: $i%" "overall"
    display_progress_bars
    sleep 0.02
done
end_progress "Kernel complete"

# Phase 2: BusyBox (20% of total)  
update_progress 40 "Starting BusyBox build..."
start_progress "busybox" 100
for i in {1..100}; do
    update_progress $i "Building BusyBox..."
    # Update overall progress proportionally  
    overall_progress=$((40 + (i * 20 / 100)))
    update_progress $overall_progress "BusyBox build: $i%" "overall"
    display_progress_bars
    sleep 0.01
done
end_progress "BusyBox complete"

# Phase 3: RootFS (20% of total)
update_progress 60 "Creating root filesystem..."
start_progress "rootfs" 100
for i in {1..100}; do
    update_progress $i "Creating rootfs..."
    # Update overall progress proportionally
    overall_progress=$((60 + (i * 20 / 100)))
    update_progress $overall_progress "RootFS: $i%" "overall"
    display_progress_bars
    sleep 0.01
done
end_progress "RootFS complete"

# Phase 4: Flash (20% of total)
update_progress 80 "Flashing device..."
start_progress "flash" 100
for i in {1..100}; do
    update_progress $i "Flashing to device..."
    # Update overall progress proportionally
    overall_progress=$((80 + (i * 20 / 100)))
    update_progress $overall_progress "Flash: $i%" "overall"
    display_progress_bars
    sleep 0.01
done
end_progress "Flash complete"

update_progress 100 "Build complete!"
end_progress "RG35HAXX build finished successfully!"

echo ""
echo "Progress tracking test completed!"
echo "Ready to build RG35HAXX with real-time progress bars!"
