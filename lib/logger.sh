#!/bin/bash
# Logging utilities for RG35HAXX Custom Linux Builder


# Guard against multiple sourcing
[[ -n "${RG35HAXX_LOGGER_LOADED:-}" ]] && return 0
export RG35HAXX_LOGGER_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

# Progress tracking variables
declare -A CURRENT_MODULE_PROGRESS
declare -A MODULE_STATUS
OVERALL_PROGRESS=0
CURRENT_MODULE=""
MODULE_TOTAL=0

# Initialize logging system
init_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$PWD/logs"
    
    # Initialize progress tracking
    CURRENT_MODULE_PROGRESS=()
    MODULE_STATUS=()
    OVERALL_PROGRESS=0
    
    # Setup terminal for progress display
    tput sc  # Save cursor position
    echo "Logging initialized for RG35HAXX build system"
}

# Start progress tracking for a module
start_progress() {
    local module="$1"
    local total="$2"
    
    CURRENT_MODULE="$module"
    MODULE_TOTAL="$total"
    CURRENT_MODULE_PROGRESS["$module"]=0
    MODULE_STATUS["$module"]="Starting..."
    
    display_progress_bars
}

# Update current module progress
update_progress() {
    local percent="$1"
    local status="$2"
    
    if [[ -n "$CURRENT_MODULE" ]]; then
        CURRENT_MODULE_PROGRESS["$CURRENT_MODULE"]="$percent"
        MODULE_STATUS["$CURRENT_MODULE"]="$status"
        
        # Calculate overall progress based on module weights
        calculate_overall_progress
        display_progress_bars
    fi
}

# End progress for current module
end_progress() {
    local final_status="$1"
    
    if [[ -n "$CURRENT_MODULE" ]]; then
        CURRENT_MODULE_PROGRESS["$CURRENT_MODULE"]=100
        MODULE_STATUS["$CURRENT_MODULE"]="$final_status"
        display_progress_bars
        CURRENT_MODULE=""
    fi
}

# Calculate overall progress
calculate_overall_progress() {
    local total=0
    local weighted_sum=0
    
    # Module weights: kernel=40%, busybox=20%, rootfs=20%, flash=20%
    if [[ -n "${CURRENT_MODULE_PROGRESS[kernel]:-}" ]]; then
        weighted_sum=$((weighted_sum + CURRENT_MODULE_PROGRESS[kernel] * 40 / 100))
        total=$((total + 40))
    fi
    if [[ -n "${CURRENT_MODULE_PROGRESS[busybox]:-}" ]]; then
        weighted_sum=$((weighted_sum + CURRENT_MODULE_PROGRESS[busybox] * 20 / 100))
        total=$((total + 20))
    fi
    if [[ -n "${CURRENT_MODULE_PROGRESS[rootfs]:-}" ]]; then
        weighted_sum=$((weighted_sum + CURRENT_MODULE_PROGRESS[rootfs] * 20 / 100))
        total=$((total + 20))
    fi
    if [[ -n "${CURRENT_MODULE_PROGRESS[flash]:-}" ]]; then
        weighted_sum=$((weighted_sum + CURRENT_MODULE_PROGRESS[flash] * 20 / 100))
        total=$((total + 20))
    fi
    
    if [[ $total -gt 0 ]]; then
        OVERALL_PROGRESS=$((weighted_sum * 100 / total))
    fi
}

# Display progress bars
display_progress_bars() {
    # Save current cursor position and move to progress area
    tput sc
    tput cup $((LINES - 4)) 0
    
    # Clear progress area
    printf "\033[K"  # Clear current line
    printf "\033[K\n"  # Clear next line
    printf "\033[K\n"  # Clear next line
    
    # Display overall progress bar
    printf "Overall Progress: "
    draw_progress_bar "$OVERALL_PROGRESS" 50
    printf " %3d%%\n" "$OVERALL_PROGRESS"
    
    # Display current module progress
    if [[ -n "$CURRENT_MODULE" ]] && [[ -n "${CURRENT_MODULE_PROGRESS[$CURRENT_MODULE]:-}" ]]; then
        printf "%-15s: " "$CURRENT_MODULE"
        draw_progress_bar "${CURRENT_MODULE_PROGRESS[$CURRENT_MODULE]}" 30
        printf " %3d%% - %s\n" "${CURRENT_MODULE_PROGRESS[$CURRENT_MODULE]}" "${MODULE_STATUS[$CURRENT_MODULE]}"
    fi
    
    # Restore cursor position
    tput rc
}

# Draw a progress bar
draw_progress_bar() {
    local percent="$1"
    local width="$2"
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    printf "["
    printf "%*s" "$filled" "" | tr ' ' '█'
    printf "%*s" "$empty" "" | tr ' ' '░'
    printf "]"
}

display_progress_bars() {
    # Save cursor position and move up to draw progress bars
    tput sc 2>/dev/null || true
    tput cuu 3 2>/dev/null || true
    
    # Draw overall progress bar
    draw_progress_bar "Overall" "$OVERALL_PROGRESS" "${GREEN}"
    
    # Draw current module progress bar
    local current_module=""
    local current_percent=0
    local current_status=""
    
    for module in "${!PROGRESS_MODULES[@]}"; do
        if [[ ${PROGRESS_MODULES[$module]} -lt 100 ]] || [[ -z "$current_module" ]]; then
            current_module="$module"
            current_percent="${PROGRESS_MODULES[$module]}"
            current_status="${PROGRESS_STATUS[$module]}"
        fi
    done
    
    if [[ -n "$current_module" ]]; then
        draw_progress_bar "$current_module" "$current_percent" "${BLUE}" "$current_status"
    fi
    
    # Restore cursor position
    tput rc 2>/dev/null || true
}

draw_progress_bar() {
    local label="$1"
    local percent="$2"
    local color="$3"
    local status="${4:-}"
    
    local width=40
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    # Build progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    # Format label to fixed width
    local formatted_label=$(printf "%-8s" "$label")
    
    # Print progress bar with status (overwrite line)
    printf "\r${color}%s${NC} [%s] %3d%% %s\n" \
           "$formatted_label" "$bar" "$percent" "${status:-}"
}

log_info() { 
    echo -e "${GREEN}[INFO $(date '+%H:%M:%S')]${NC} $1" 
}

log_warn() { 
    echo -e "${YELLOW}[WARN $(date '+%H:%M:%S')]${NC} $1" 
}

log_error() { 
    echo -e "${RED}[ERROR $(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS $(date '+%H:%M:%S')]${NC} ✅ $1"
}

log_step() { 
    echo -e "\n${BLUE}=== $1 ===${NC}" 
}

# Legacy function names for compatibility
log() { log_info "$@"; }
warn() { log_warn "$@"; }
error() { log_error "$@"; exit 1; }
step() { log_step "$@"; }



show_progress() {
    local current=$1
    local total=$2
    local description="$3"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${BLUE}%s${NC} [" "$description"
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%%" $percentage
    
    if [ $current -eq $total ]; then
        echo
    fi
}
