#!/bin/bash
# Enhanced logging utilities for RG35XX-H Custom Build

# Guard against multiple sourcing (do not export the guard; keep it shell-local)
[[ -n "${RG35HAXX_LOGGER_LOADED:-}" ]] && return 0
RG35HAXX_LOGGER_LOADED=1

# Try to source constants for colors, but don't fail if not available
source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh" 2>/dev/null || true

# Logging levels
export LOG_LEVEL_ERROR=0
export LOG_LEVEL_WARN=1
export LOG_LEVEL_INFO=2
export LOG_LEVEL_DEBUG=3

# Default log level
export CURRENT_LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Set log directory
LOGDIR="${PWD}/logs"
mkdir -p "$LOGDIR"
export LOG_FILE="${LOG_FILE:-$LOGDIR/build.log}"

# Initialize logging
init_logging() {
    echo "RG35XX-H Custom Build Log - Started at $(date '+%F %T')" > "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"
    log_info "Logging initialized"
}

# Internal logging function
_log() {
    local level="$1"
    local color="$2"
    local level_name="$3"
    shift 3
    local message="$*"
    local timestamp=$(date '+%H:%M:%S')
    
    # Always log to file
    echo "[${level_name}] $(date '+%F %T') - $message" >> "$LOG_FILE"
    
    # Only show on console if level is appropriate
    if [[ "$level" -le "$CURRENT_LOG_LEVEL" ]]; then
        echo -e "${color}[${level_name} ${timestamp}]${NC} $message"
    fi
}

# Log error message (always shown)
log_error() {
    _log $LOG_LEVEL_ERROR "$RED" "ERROR" "$@"
}

# Log warning message
log_warn() {
    _log $LOG_LEVEL_WARN "$YELLOW" "WARN" "$@"
}

# Log info message
log_info() {
    _log $LOG_LEVEL_INFO "$GREEN" "INFO" "$@"
}

# Log debug message
log_debug() {
    _log $LOG_LEVEL_DEBUG "$BLUE" "DEBUG" "$@"
}

# Log success message (same level as info but with success tag)
log_success() {
    _log $LOG_LEVEL_INFO "$GREEN" "SUCCESS" "$@"
}

# Log section header
log_step() {
    echo ""
    echo -e "${BLUE}=== $* ===${NC}"
    echo ""
    
    echo "" >> "$LOG_FILE"
    echo "=== $* ===" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Set log level
set_log_level() {
    local level="$1"
    case "$level" in
        error) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        warn)  CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN ;;
        info)  CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
        debug) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        *)     log_warn "Unknown log level: $level. Using info level." 
               CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
    esac
    log_info "Log level set to: $level"
}

# Enhanced progress tracking with visual bar
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
    
    # Calculate visual progress bar
    local width=40
    local completed=$((width * percent / 100))
    local bar=""
    for ((i=0; i<completed; i++)); do
        bar+="="
    done
    for ((i=completed; i<width; i++)); do
        bar+=" "
    done
    
    # Print progress
    printf "\r${MODULE_NAME}: [${bar}] ${percent}%% ${status}     "
    
    # Also log to file
    if [[ -n "$status" ]]; then
        echo "[PROGRESS] $(date '+%F %T') - $MODULE_NAME: $percent% - $status" >> "$LOG_FILE"
    else
        echo "[PROGRESS] $(date '+%F %T') - $MODULE_NAME: $percent%" >> "$LOG_FILE"
    fi
    
    # Print newline when complete
    if [ "$percent" -eq "100" ]; then
        echo ""
    fi
}

end_progress() {
    local final_status="${1:-Done}"
    MODULE_PROGRESS=100
    update_progress 100 "$final_status"
    log_info "$MODULE_NAME completed: $final_status"
}

# Better error handling with stack trace
handle_error() {
    local exit_code=$?
    local message="$1"
    local line_no="${BASH_LINENO[0]}"
    local function_name="${FUNCNAME[1]}"
    local file="${BASH_SOURCE[1]}"
    
    log_error "$message (code: $exit_code) in $function_name:$line_no [$file]"
    
    # Print stack trace
    log_error "Stack trace:"
    local i=1
    while caller $i >/dev/null; do
        local frame_info=($(caller $i))
        log_error "  $i: ${frame_info[2]}:${frame_info[0]} in ${frame_info[1]}"
        ((i++))
    done
    
    return $exit_code
}

# Backwards compatibility
log() { log_info "$@"; }
warn() { log_warn "$@"; }
error() { log_error "$@"; exit 1; }
step() { log_step "$@"; }

# Initialize logging on load
init_logging
