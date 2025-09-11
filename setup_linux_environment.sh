#!/bin/bash
# setup_linux_environment.sh - Complete Linux environment setup for RG35XX-H builder

echo "=================================================================="
echo "  RG35XX-H Custom Linux Builder - Linux Environment Setup"
echo "=================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { print_error "Failed to change to script directory"; exit 1; }

print_status "Setting up RG35XX-H Custom Linux Builder environment..."

# 1. Make all shell scripts executable
print_status "Making all shell scripts executable..."
find . -name "*.sh" -type f -exec chmod +x {} \;
print_status "✓ All shell scripts are now executable"

# 2. Verify directory structure
print_status "Verifying plugin architecture..."
required_dirs=("config" "core" "lib" "modules" "builders" "plugins" "tools" "flash")
missing_dirs=0

for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        print_error "Missing required directory: $dir"
        missing_dirs=$((missing_dirs + 1))
    else
        print_status "✓ Directory found: $dir"
    fi
done

if [ $missing_dirs -gt 0 ]; then
    print_error "Missing $missing_dirs required directories. Please check your installation."
    exit 1
fi

# 3. Check for required system dependencies
print_status "Checking system dependencies..."

# Check if we're running as root (for package installation)
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root. This is okay for dependency installation."
else
    print_warning "Not running as root. You may need sudo for some operations."
fi

# Check for basic tools
required_tools=("make" "gcc" "git" "wget" "bc" "bison" "flex" "libssl-dev" "libelf-dev")
missing_tools=()

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null && ! dpkg -l | grep -q "$tool"; then
        missing_tools+=("$tool")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    print_warning "Missing tools: ${missing_tools[*]}"
    print_status "Run './core/install_dependencies.sh' to install missing dependencies"
else
    print_status "✓ All required tools are available"
fi

# 4. Test basic functionality
print_status "Testing basic functionality..."

# Test if main.sh can load
if ./main.sh --help &> /dev/null; then
    print_status "✓ Main script loads successfully"
else
    print_error "✗ Main script failed to load"
    print_status "Testing individual components..."
    
    # Test logger
    if source lib/logger.sh 2>/dev/null; then
        print_status "✓ Logger library loads"
    else
        print_error "✗ Logger library failed to load"
    fi
    
    # Test constants
    if source config/constants.sh 2>/dev/null; then
        print_status "✓ Constants configuration loads"
    else
        print_error "✗ Constants configuration failed to load"
    fi
fi

# 5. Create logs directory if it doesn't exist
if [ ! -d "logs" ]; then
    mkdir -p logs
    print_status "✓ Created logs directory"
fi

# 6. Display usage information
echo ""
echo "=================================================================="
echo -e "${GREEN}  Setup Complete!${NC}"
echo "=================================================================="
echo ""
echo "Available commands:"
echo "  ./main.sh --help              Show all available options"
echo "  ./main.sh --build-rg35xxh     Build the RG35XX-H custom Linux"
echo "  ./main.sh --install-deps      Install required dependencies"
echo "  ./main.sh --backup            Backup SD card"
echo "  ./main.sh --diagnose          Run diagnostics"
echo ""
echo "Plugin directories:"
for dir in "${required_dirs[@]}"; do
    echo "  $dir/ - $(ls "$dir" | wc -l) files"
done
echo ""
echo "Next steps:"
echo "1. Run: ./main.sh --install-deps (if you haven't already)"
echo "2. Run: ./main.sh --build-rg35xxh (to start building)"
echo ""
echo "For more information, see the documentation in docs/"
echo "=================================================================="
