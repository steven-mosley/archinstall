#!/bin/bash
# Utility functions for the installer

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${BLUE}[${timestamp}]${NC} $*" | tee -a "$LOG_FILE"
}

# Debug logging function
debug() {
    if [[ "$DEBUG" -eq 1 ]]; then
        local timestamp
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo -e "${YELLOW}[DEBUG ${timestamp}]${NC} $*" | tee -a "$LOG_FILE"
    fi
}

# Function to get user input
prompt() {
    local message="$1"
    local var_name="$2"
    local default="${3:-}"
    
    if [[ -n "$default" ]]; then
        message+=" [$default]: "
    else
        message+=": "
    fi
    
    # Fix SC2034 by directly assigning to the variable name instead of using an intermediate variable
    read -r -p "$message" "$var_name"
    
    # If empty and we have a default, use the default
    if [[ -z "${!var_name}" && -n "$default" ]]; then
        eval "$var_name=\$default"
    fi
}

# Error function
error() {
    log "${RED}ERROR:${NC} $*"
}

# Load all module files
load_modules() {
    log "Loading modules..."
    for module in "$SCRIPT_DIR/modules"/*.sh; do
        if [[ "$module" != "$SCRIPT_DIR/modules/utils.sh" ]]; then
            # shellcheck disable=SC1090
            source "$module" || { error "Failed to load $module"; exit 1; }
        fi
    done
}

handle_error() {
    local exit_code=$?
    local line_number=$1
    log "${RED}ERROR: Command on line $line_number failed (status $exit_code)${NC}"
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

spinner() {
    local pid=$1
    local msg=$2
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r%s%s%s %s" "${GREEN}==>" "${NC}" "$msg" "${spin:$i:1}" > /dev/tty
        sleep 0.1
    done
    printf "\r%s%s%s Done" "${GREEN}==>" "${NC}" "$msg" > /dev/tty
}
