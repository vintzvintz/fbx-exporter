#!/bin/bash
# Fix permissions for FBX Exporter Development Environment
# This script detects current user UID/GID and updates .env automatically

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

# Detect current user UID/GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(id -un)

log_info "Detected current user: $CURRENT_USER (UID:$CURRENT_UID, GID:$CURRENT_GID)"

# Update or create .env file
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"

if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$ENV_EXAMPLE" ]]; then
        log_info "Creating .env from .env.example"
        cp "$ENV_EXAMPLE" "$ENV_FILE"
    else
        log_error ".env.example not found, cannot create .env"
        exit 1
    fi
fi

# Update UID/GID in .env file
log_info "Updating .env with detected UID/GID"

# Use sed to update or add DEV_UID and DEV_GID
if grep -q "^DEV_UID=" "$ENV_FILE"; then
    sed -i "s/^DEV_UID=.*/DEV_UID=$CURRENT_UID/" "$ENV_FILE"
    log_info "Updated DEV_UID=$CURRENT_UID"
else
    echo "DEV_UID=$CURRENT_UID" >> "$ENV_FILE"
    log_info "Added DEV_UID=$CURRENT_UID"
fi

if grep -q "^DEV_GID=" "$ENV_FILE"; then
    sed -i "s/^DEV_GID=.*/DEV_GID=$CURRENT_GID/" "$ENV_FILE"
    log_info "Updated DEV_GID=$CURRENT_GID"
else
    echo "DEV_GID=$CURRENT_GID" >> "$ENV_FILE"
    log_info "Added DEV_GID=$CURRENT_GID"
fi

# Load updated environment
# shellcheck source=/dev/null
source "$ENV_FILE"

# Create data directories if they don't exist
DATA_DIRS=(
    "${PROMETHEUS_DATA_PATH:-./data/prometheus}"
    "${GRAFANA_DATA_PATH:-./data/grafana}"
)

log_info "Creating data directories if needed..."
for dir in "${DATA_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            log_action "Run: sudo mkdir -p '$dir' && sudo chown $CURRENT_USER:$CURRENT_USER '$dir'"
            exit 1
        }
    fi
done

# Function to fix permissions with error handling
fix_permissions() {
    local path="$1"
    local uid="$2"
    local gid="$3"
    local description="$4"

    if [[ ! -e "$path" ]]; then
        log_warn "$description directory not found: $path"
        return 0
    fi

    log_info "Fixing $description permissions: $path"

    # Try to change ownership without sudo first
    if chown -R "$uid:$gid" "$path" 2>/dev/null; then
        log_info "✓ Ownership changed successfully"
    else
        log_error "Failed to change ownership of $path"
        log_action "Run: sudo chown -R $uid:$gid '$path'"
        return 1
    fi

    # Try to change permissions
    if chmod -R 755 "$path" 2>/dev/null; then
        log_info "✓ Permissions changed successfully"
    else
        log_error "Failed to change permissions of $path"
        log_action "Run: sudo chmod -R 755 '$path'"
        return 1
    fi

    return 0
}

# Track if any operations failed
FAILED_OPERATIONS=()

# Fix data directory permissions
PROMETHEUS_DIR="${PROMETHEUS_DATA_PATH:-./data/prometheus}"
if ! fix_permissions "$PROMETHEUS_DIR" "$CURRENT_UID" "$CURRENT_GID" "Prometheus data"; then
    FAILED_OPERATIONS+=("Prometheus data: $PROMETHEUS_DIR")
fi

GRAFANA_DIR="${GRAFANA_DATA_PATH:-./data/grafana}"
if ! fix_permissions "$GRAFANA_DIR" "$CURRENT_UID" "$CURRENT_GID" "Grafana data"; then
    FAILED_OPERATIONS+=("Grafana data: $GRAFANA_DIR")
fi

# Fix secrets permissions (should be readable by containers)
SECRETS_DIR="secrets"
if [[ -d "$SECRETS_DIR" ]]; then
    log_info "Fixing secrets permissions: $SECRETS_DIR"

    # Secrets should be readable only by owner (containers run with same UID)
    if find "$SECRETS_DIR" -type f -name "*.txt" -exec chmod 600 {} \; 2>/dev/null && \
       find "$SECRETS_DIR" -type f -name "*.json" -exec chmod 600 {} \; 2>/dev/null && \
       chmod 700 "$SECRETS_DIR" 2>/dev/null; then
        log_info "✓ Secrets permissions fixed (owner-only access)"
    else
        log_error "Failed to fix secrets permissions"
        log_action "Run: sudo find '$SECRETS_DIR' -type f \\( -name '*.txt' -o -name '*.json' \\) -exec chmod 600 {} \\; && sudo chmod 700 '$SECRETS_DIR'"
        FAILED_OPERATIONS+=("Secrets: $SECRETS_DIR")
    fi
fi

# Summary
echo ""
if [[ ${#FAILED_OPERATIONS[@]} -eq 0 ]]; then
    log_info "✓ All permissions fixed successfully!"
    log_info "Environment configured with:"
    log_info "  - DEV_UID=$CURRENT_UID"
    log_info "  - DEV_GID=$CURRENT_GID"
    log_info ""
    log_info "You can now run: docker compose up -d"
else
    log_warn "Some operations failed. Manual intervention required:"
    echo ""
    log_action "Run the following commands to fix remaining issues:"
    echo ""
    for op in "${FAILED_OPERATIONS[@]}"; do
        echo "# Fix $op"
    done
    echo ""
    log_info "After running the suggested commands, you can start with: docker compose up -d"
fi