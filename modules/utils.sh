# utils.sh
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    [[ $DEBUG -eq 1 ]] && echo -e "${GREEN}==> ${NC}$message" || echo -e "${GREEN}==> ${NC}$message" > /dev/tty
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
        printf "\r${GREEN}==> ${NC}$msg ${spin:$i:1}" > /dev/tty
        sleep 0.1
    done
    printf "\r${GREEN}==> ${NC}$msg Done" > /dev/tty
}

prompt() {
    local message="$1"
    local varname="$2"
    echo -e "${YELLOW}$message${NC}" > /dev/tty
    read -r "$varname" < /dev/tty
}
