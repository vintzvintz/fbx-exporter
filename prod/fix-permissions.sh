#!/bin/bash
# Fix permissions for FBX Exporter Production Environment
# This script analyzes required permissions and provides commands for the user

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_action() {
    echo -e "${BLUE}[ACTION]${NC} $1"
}

# Load environment variables from .env if it exists
if [[ -f .env ]]; then
    log_info "Loading environment from .env"
    # shellcheck source=/dev/null
    source .env
else
    log_warn ".env file not found, using defaults from .env.example"
fi

# Extract UID/GID from docker-compose.yml (production uses fixed UIDs)
get_prod_uid_gid() {
    local service="$1"

    if [[ -f docker-compose.yml ]]; then
        # Extract user line for the service
        local user_line
        user_line=$(grep -A 10 "^  $service:" docker-compose.yml | grep "user:" | head -1 || true)

        if [[ -n "$user_line" ]]; then
            # Extract numeric UID:GID like: user: "65534:65534"
            local user_spec
            user_spec=$(echo "$user_line" | sed -n 's/.*user:[[:space:]]*"\([0-9]*:[0-9]*\)".*/\1/p')

            if [[ -n "$user_spec" ]]; then
                echo "$user_spec"
                return
            fi
        fi
    fi

    # Fallback defaults for production
    case "$service" in
        "freebox-exporter") echo "65534:65534" ;;
        "prometheus") echo "65534:65534" ;;
        "grafana") echo "472:472" ;;
        *) echo "65534:65534" ;;
    esac
}

# Get UID/GID for each service
FREEBOX_USER=$(get_prod_uid_gid "freebox-exporter")
PROMETHEUS_USER=$(get_prod_uid_gid "prometheus")
GRAFANA_USER=$(get_prod_uid_gid "grafana")

FREEBOX_UID=${FREEBOX_USER%:*}
FREEBOX_GID=${FREEBOX_USER#*:}
PROMETHEUS_UID=${PROMETHEUS_USER%:*}
PROMETHEUS_GID=${PROMETHEUS_USER#*:}
GRAFANA_UID=${GRAFANA_USER%:*}
GRAFANA_GID=${GRAFANA_USER#*:}

log_info "Detected service UIDs/GIDs from docker-compose.yml:"
log_info "  - Freebox Exporter: $FREEBOX_UID:$FREEBOX_GID"
log_info "  - Prometheus: $PROMETHEUS_UID:$PROMETHEUS_GID"
log_info "  - Grafana: $GRAFANA_UID:$GRAFANA_GID"

# Production data directories (fixed paths)
DATA_DIRS=(
    "./prometheus_data"
    "./grafana_data"
    "./secrets"
)

# Critical files that must exist
CRITICAL_FILES=(
    "./docker-compose.yml"
    "./secrets/freebox_token.json"
    "./secrets/grafana_admin_user.txt"
    "./secrets/grafana_admin_password.txt"
)

echo ""
log_info "=== PRODUCTION ENVIRONMENT SETUP ==="
echo ""

# Check if directories exist and analyze permissions
COMMANDS_TO_RUN=()
MISSING_DIRS=()
MISSING_FILES=()

for dir in "${DATA_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        MISSING_DIRS+=("$dir")
    fi
done

for file in "${CRITICAL_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

# Generate commands for missing directories
if [[ ${#MISSING_DIRS[@]} -gt 0 ]]; then
    log_warn "Missing directories detected:"
    for dir in "${MISSING_DIRS[@]}"; do
        echo "  - $dir"
    done
    echo ""
    log_action "Create missing directories:"
    for dir in "${MISSING_DIRS[@]}"; do
        COMMANDS_TO_RUN+=("mkdir -p '$dir'")
    done
fi

# Generate permission commands
log_action "Set proper ownership and permissions:"

# Prometheus data
COMMANDS_TO_RUN+=("sudo chown -R $PROMETHEUS_UID:$PROMETHEUS_GID './prometheus_data'")
COMMANDS_TO_RUN+=("chmod -R 755 './prometheus_data'")

# Grafana data
COMMANDS_TO_RUN+=("sudo chown -R $GRAFANA_UID:$GRAFANA_GID './grafana_data'")
COMMANDS_TO_RUN+=("chmod -R 755 './grafana_data'")

# Secrets (production security)
COMMANDS_TO_RUN+=("sudo chown -R root:root './secrets'")
COMMANDS_TO_RUN+=("find './secrets' -type f -exec chmod 640 {} \\;")
COMMANDS_TO_RUN+=("chmod 750 './secrets'")

# Grafana provisioning if it exists
if [[ -d "./grafana_provisioning" ]]; then
    COMMANDS_TO_RUN+=("sudo chown -R $GRAFANA_UID:$GRAFANA_GID './grafana_provisioning'")
    COMMANDS_TO_RUN+=("find './grafana_provisioning' -type f -exec chmod 644 {} \\;")
    COMMANDS_TO_RUN+=("find './grafana_provisioning' -type d -exec chmod 755 {} \\;")
fi

# Display all commands to run
echo ""
log_info "Execute the following commands:"
echo ""
echo "# Fix permissions for production environment"
for cmd in "${COMMANDS_TO_RUN[@]}"; do
    echo "$cmd"
done

# Check for missing files
if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo ""
    log_error "Missing critical files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    log_action "Ensure these files exist before starting services"
    exit 1
fi

echo ""
log_info "Security notes for production:"
log_info "  - Secrets have restrictive permissions (640/750)"
log_info "  - Services run with non-root users (65534 for most, 472 for Grafana)"
log_info "  - Data directories owned by respective service users"
log_info "  - Root owns secrets for additional security"
echo ""
log_info "After running the commands above, start with: docker compose up -d"