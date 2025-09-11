#!/bin/bash
# make_executable.sh - Make all shell scripts executable in Linux

echo "Making all shell scripts executable..."

# Find all .sh files and make them executable
find . -name "*.sh" -type f -exec chmod +x {} \; -print

echo "All shell scripts are now executable!"
echo "Use 'ls -la' to verify permissions."
