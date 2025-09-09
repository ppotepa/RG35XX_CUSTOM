#!/bin/bash
# RG35XX H DTB Fallback Script
# This script will cycle through DTB variants and packaging modes to find a working combination

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
cd "$SCRIPT_DIR"

# Define DTB variants
DTB_VARIANTS=(
  "sun50i-h700-anbernic-rg35xx-h.dtb"
  "sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb"
  "sun50i-h700-rg40xx-h.dtb"
)

# Define packaging modes
PACKAGE_MODES=("catdt" "with-dt")

usage() {
  echo "RG35XX H DTB Fallback Script"
  echo "Usage: $0 [--start-dtb=N] [--start-package=MODE]"
  echo ""
  echo "This script will try different DTB variants and packaging modes"
  echo "to find a working combination for your device."
  echo ""
  echo "DTB variants:"
  for i in "${!DTB_VARIANTS[@]}"; do
    echo "  $i: ${DTB_VARIANTS[$i]}"
  done
  echo ""
  echo "Packaging modes:"
  echo "  catdt: Concatenate kernel Image + DTB"
  echo "  with-dt: Keep DTB separate with --dt option"
  echo ""
  echo "Examples:"
  echo "  $0                      # Try all combinations"
  echo "  $0 --start-dtb=1        # Start with second DTB variant"
  echo "  $0 --start-package=with-dt  # Start with with-dt packaging"
  exit 1
}

# Parse arguments
START_DTB=0
START_PACKAGE="catdt"

while [[ $# -gt 0 ]]; do
  case $1 in
    --start-dtb=*)
      START_DTB="${1#*=}"
      if ! [[ "$START_DTB" =~ ^[0-2]$ ]]; then
        echo "ERROR: DTB index must be 0, 1, or 2"
        exit 1
      fi
      shift
      ;;
    --start-package=*)
      START_PACKAGE="${1#*=}"
      if [[ "$START_PACKAGE" != "catdt" && "$START_PACKAGE" != "with-dt" ]]; then
        echo "ERROR: Package mode must be 'catdt' or 'with-dt'"
        exit 1
      fi
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      usage
      ;;
  esac
done

# Confirm with user
echo "===== RG35XX H DTB Fallback Script ====="
echo "This script will try different DTB variants and packaging modes"
echo "to find a working combination for your device."
echo ""
echo "Press CTRL+C at any time to stop the script."
echo ""
read -p "Press ENTER to start trying different combinations..."

# Start from specified combination
dtb_index=$START_DTB
package_mode_index=0
if [[ "$START_PACKAGE" == "with-dt" ]]; then
  package_mode_index=1
fi

attempt=1
max_attempts=$((${#DTB_VARIANTS[@]} * ${#PACKAGE_MODES[@]}))

# Loop through all combinations
while true; do
  dtb="${DTB_VARIANTS[$dtb_index]}"
  package="${PACKAGE_MODES[$package_mode_index]}"
  
  echo ""
  echo "==== Attempt $attempt of $max_attempts ===="
  echo "Using DTB: $dtb (index: $dtb_index)"
  echo "Using packaging mode: $package"
  echo ""
  
  # Run build with current settings
  echo "Running build with current settings..."
  sudo ./run_ubuntu.sh --skip-build --skip-backup --dtb=$dtb_index --package=$package
  
  echo ""
  echo "Build completed. Check if the device booted correctly."
  echo "If not, press ENTER to try the next combination."
  echo "If it worked, press CTRL+C to exit."
  read
  
  # Move to next combination
  package_mode_index=$((package_mode_index + 1))
  if [[ $package_mode_index -ge ${#PACKAGE_MODES[@]} ]]; then
    package_mode_index=0
    dtb_index=$((dtb_index + 1))
    if [[ $dtb_index -ge ${#DTB_VARIANTS[@]} ]]; then
      dtb_index=0
    fi
  fi
  
  attempt=$((attempt + 1))
  if [[ $attempt -gt $max_attempts ]]; then
    echo "All combinations tried. No successful boot found."
    exit 1
  fi
done
