#!/bin/bash
# Fix permissions for FBX Exporter Production Environment
# This script sets proper ownership and permissions for production data directories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

log_info "Freebox Exporter will run as UID:GID = $FREEBOX_UID:$FREEBOX_GID"
log_info "Prometheus will run as UID:GID = $PROMETHEUS_UID:$PROMETHEUS_GID"
log_info "Grafana will run as UID:GID = $GRAFANA_UID:$GRAFANA_GID"

# Production data directories (fixed paths)
DATA_DIRS=(
    "./prometheus_data"
    "./grafana_data"
    "./secrets"
)

# Create data directories if they don't exist
for dir in "${DATA_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir"
    fi
done

# Fix Prometheus data permissions
PROMETHEUS_DIR="./prometheus_data"
if [[ -d "$PROMETHEUS_DIR" ]]; then
    log_info "Fixing Prometheus data permissions: $PROMETHEUS_DIR"
    sudo chown -R "$PROMETHEUS_UID:$PROMETHEUS_GID" "$PROMETHEUS_DIR"
    chmod -R 755 "$PROMETHEUS_DIR"
    log_info "Prometheus permissions fixed"
fi

# Fix Grafana data permissions
GRAFANA_DIR="./grafana_data"
if [[ -d "$GRAFANA_DIR" ]]; then
    log_info "Fixing Grafana data permissions: $GRAFANA_DIR"
    sudo chown -R "$GRAFANA_UID:$GRAFANA_GID" "$GRAFANA_DIR"
    chmod -R 755 "$GRAFANA_DIR"
    log_info "Grafana permissions fixed"
fi

# Fix secrets permissions (production security)
SECRETS_DIR="./secrets"
if [[ -d "$SECRETS_DIR" ]]; then
    log_info "Fixing secrets permissions: $SECRETS_DIR"

    # Secrets should be readable only by root and the service users
    # More restrictive than dev environment
    find "$SECRETS_DIR" -type f -name "*.txt" -exec chmod 600 {} \;
    find "$SECRETS_DIR" -type f -name "*.json" -exec chmod 600 {} \;
    chmod 700 "$SECRETS_DIR"

    # Make sure Docker can read the secrets by setting proper ownership
    # Keep root ownership but allow group read for Docker
    sudo chown -R root:root "$SECRETS_DIR"
    find "$SECRETS_DIR" -type f -exec chmod 640 {} \;
    chmod 750 "$SECRETS_DIR"

    log_info "Secrets permissions fixed (production security)"
fi

# Fix Grafana provisioning permissions if it exists
PROVISIONING_DIR="./grafana_provisioning"
if [[ -d "$PROVISIONING_DIR" ]]; then
    log_info "Fixing Grafana provisioning permissions: $PROVISIONING_DIR"
    sudo chown -R "$GRAFANA_UID:$GRAFANA_GID" "$PROVISIONING_DIR"
    chmod -R 644 "$PROVISIONING_DIR"
    find "$PROVISIONING_DIR" -type d -exec chmod 755 {} \;
    log_info "Grafana provisioning permissions fixed"
fi

# Verify critical files exist
log_info "Verifying critical configuration files..."

CRITICAL_FILES=(
    "./docker-compose.yml"
    "./secrets/freebox_token.json"
    "./secrets/grafana_admin_user.txt"
    "./secrets/grafana_admin_password.txt"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        log_error "Critical file missing: $file"
        log_error "Please ensure all required files are present before starting services"
        exit 1
    else
        log_info "✓ Found: $file"
    fi
done

# Summary
log_info "Production permission fix completed successfully!"
log_info "Security notes:"
log_info "  - Secrets have restrictive permissions (640/750)"
log_info "  - Services run with non-root users"
log_info "  - Data directories properly owned by service users"
log_info ""
log_info "You can now run: docker compose up -d"