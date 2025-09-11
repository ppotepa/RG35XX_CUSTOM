#!/bin/bash
# RG35XX-H model plugin
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$PLUGIN_DIR/../.." && pwd)"

source "$ROOT_DIR/config/constants.sh"
source "$ROOT_DIR/lib/logger.sh"
source "$ROOT_DIR/model/plugin_api.sh"

model_name() { echo "RG35XX-H"; }

model_init() {
  # Any model-specific env defaults can be set here
  export ACTIVE_DTB="${ACTIVE_DTB:-${DTB_VARIANTS[0]}}"
}

model_help() {
  cat <<EOF
$(model_name) Plugin
  Builds and flashes the RG35XX-H model.
  Examples:
    --model=rg35xxh build        Build artifacts
    --model=rg35xxh flash        Flash to device (requires root)
    --model=rg35xxh build+flash  Build then flash
EOF
}

model_build() {
  bash "$ROOT_DIR/core/build_rg35xxh.sh" "$@"
}

model_flash() {
  bash "$ROOT_DIR/flash/flasher.sh" "$@"
}
