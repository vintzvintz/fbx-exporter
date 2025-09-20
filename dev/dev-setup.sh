#!/bin/bash
# Development Environment Setup for FBX Exporter
# Automatically configures UID/GID, updates .env, and sets up permissions

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
    "./data/prometheus"
    "./data/grafana"
    "./secrets"
)

MISSING_DIRS=()
for dir in "${DATA_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        MISSING_DIRS+=("$dir")
    fi
done

if [[ ${#MISSING_DIRS[@]} -gt 0 ]]; then
    log_info "Creating missing directories..."
    for dir in "${MISSING_DIRS[@]}"; do
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            log_action "Run: sudo mkdir -p '$dir' && sudo chown $CURRENT_USER:$CURRENT_USER '$dir'"
            exit 1
        }
    done
fi

# Create secrets from examples if they don't exist
SECRETS=(
    "grafana_admin_user.txt"
    "grafana_admin_password.txt"
    "freebox_token.json"
)

log_info "Creating secrets from examples if needed..."
for secret in "${SECRETS[@]}"; do
    secret_file="./secrets/$secret"
    example_file="./secrets/$secret.example"

    if [[ ! -f "$secret_file" && -f "$example_file" ]]; then
        log_info "Creating $secret from example"
        cp "$example_file" "$secret_file"
    fi
done

# Generate permission commands
COMMANDS_TO_RUN=()

# Data directories owned by current user
PROMETHEUS_DIR="./data/prometheus"
GRAFANA_DIR="./data/grafana"
SECRETS_DIR="./secrets"

COMMANDS_TO_RUN+=("chown -R $CURRENT_UID:$CURRENT_GID '$PROMETHEUS_DIR'")
COMMANDS_TO_RUN+=("chmod -R 755 '$PROMETHEUS_DIR'")
COMMANDS_TO_RUN+=("chown -R $CURRENT_UID:$CURRENT_GID '$GRAFANA_DIR'")
COMMANDS_TO_RUN+=("chmod -R 755 '$GRAFANA_DIR'")

# Secrets owned by current user (dev environment - less restrictive)
COMMANDS_TO_RUN+=("chown -R $CURRENT_UID:$CURRENT_GID '$SECRETS_DIR'")
COMMANDS_TO_RUN+=("find '$SECRETS_DIR' -type f -exec chmod 600 {} \\;")
COMMANDS_TO_RUN+=("chmod 700 '$SECRETS_DIR'")

# Try to execute commands without sudo first
log_action "Fixing permissions..."
FAILED_OPERATIONS=()

for cmd in "${COMMANDS_TO_RUN[@]}"; do
    # Remove quotes for actual execution
    cmd_clean=$(echo "$cmd" | sed "s/'//g")
    if ! eval "$cmd_clean" 2>/dev/null; then
        FAILED_OPERATIONS+=("$cmd")
    fi
done

# Summary and instructions
if [[ ${#FAILED_OPERATIONS[@]} -eq 0 ]]; then
    log_info "✓ Setup complete! Environment configured with DEV_UID=$CURRENT_UID, DEV_GID=$CURRENT_GID"
    log_action "Start with: docker compose up -d"
else
    log_warn "Some operations failed. Execute the following commands:"
    echo ""
    for cmd in "${FAILED_OPERATIONS[@]}"; do
        echo "$cmd"
    done
fi