#!/bin/bash
# Simple, robust logging utilities for RG35HAXX build system

[[ -n "${RG35HAXX_LOGGER_LOADED:-}" ]] && return 0
export RG35HAXX_LOGGER_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh" || true

LOGDIR="${PWD}/logs"
mkdir -p "$LOGDIR"

init_logging() {
    echo "[INFO] $(date '+%F %T') - Logging initialized" > "$LOGDIR/build.log"
}

log_info() {
    echo -e "${GREEN}[INFO $(date '+%H:%M:%S')]${NC} $1"
    echo "[INFO] $(date '+%F %T') - $1" >> "$LOGDIR/build.log"
}

log_warn() {
    echo -e "${YELLOW}[WARN $(date '+%H:%M:%S')]${NC} $1"
    echo "[WARN] $(date '+%F %T') - $1" >> "$LOGDIR/build.log"
}

log_error() {
    echo -e "${RED}[ERROR $(date '+%H:%M:%S')]${NC} $1"
    echo "[ERROR] $(date '+%F %T') - $1" >> "$LOGDIR/build.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS $(date '+%H:%M:%S')]${NC} $1"
    echo "[SUCCESS] $(date '+%F %T') - $1" >> "$LOGDIR/build.log"
}

log_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
    echo "[STEP] $(date '+%F %T') - $1" >> "$LOGDIR/build.log"
}

# Simple progress helpers (module-name, percent, status)
start_progress() {
    MODULE_NAME="$1"
    MODULE_TOTAL=${2:-100}
    MODULE_PROGRESS=0
    log_info "Starting progress for $MODULE_NAME"
}

update_progress() {
    # Supports two calling styles: (percent) or (percent, status)
    local percent="$1"
    local status="${2:-}"
    MODULE_PROGRESS="$percent"
    if [[ -n "$status" ]]; then
        log_info "$MODULE_NAME: $percent% - $status"
    else
        log_info "$MODULE_NAME: $percent%"
    fi
}

end_progress() {
    local final_status="${1:-Done}"
    MODULE_PROGRESS=100
    log_info "$MODULE_NAME completed: $final_status"
}

# Backwards compatibility
log() { log_info "$@"; }
warn() { log_warn "$@"; }
error() { log_error "$@"; exit 1; }
step() { log_step "$@"; }
