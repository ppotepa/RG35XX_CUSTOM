#!/bin/bash
# Logging utilities for RG35XX_H Custom Linux Builder

source "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

log() { 
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" 
}

warn() { 
    echo -e "${YELLOW}[WARN]${NC} $1" 
}

error() { 
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1 
}

step() { 
    echo -e "\n${BLUE}=== $1 ===${NC}" 
}

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
