#!/usr/bin/env bash
#
# cleanup.sh - Clean up Colima and Docker resources for the remote builder
#
# This script helps troubleshoot issues by completely cleaning up
# the remote builder environment and allowing a fresh start.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="nix-remote-builder"

# Configure Docker to use Colima
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "Remote Builder Cleanup Script"
echo "============================="
echo ""

log_info "This script will clean up all remote builder resources:"
log_info "- Stop and remove the Docker container"
log_info "- Stop and delete the Colima VM"
log_info "- Remove Nix remote builder configuration"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

echo ""

# Stop and remove Docker container
log_info "Cleaning up Docker container..."
if docker ps | grep -q "$CONTAINER_NAME"; then
    log_info "Stopping Docker container..."
    docker stop "$CONTAINER_NAME"
    log_success "Stopped Docker container"
fi

if docker ps -a | grep -q "$CONTAINER_NAME"; then
    log_info "Removing Docker container..."
    docker rm "$CONTAINER_NAME"
    log_success "Removed Docker container"
else
    log_info "No Docker container found"
fi

# Remove Docker images
log_info "Cleaning up Docker images..."
if docker images nix-remote-builder:latest --format "table {{.Repository}}:{{.Tag}}" | grep -q "nix-remote-builder:latest"; then
    log_info "Removing Docker image 'nix-remote-builder:latest'..."
    docker rmi nix-remote-builder:latest
    log_success "Removed Docker image"
else
    log_info "No Docker image found"
fi

# Stop and delete Colima
log_info "Cleaning up Colima..."
if colima status &>/dev/null; then
    log_info "Stopping Colima..."
    if timeout 30 colima stop; then
        log_success "Stopped Colima"
    else
        log_warning "Colima stop timed out, forcing deletion..."
    fi
fi

if colima list 2>/dev/null | grep -q "colima"; then
    log_info "Deleting Colima VM..."
    if timeout 30 colima delete --force colima; then
        log_success "Deleted Colima VM"
    else
        log_warning "Colima delete timed out, cleaning up manually..."
        # Try to clean up Colima files if the command hangs
        if [[ -d "$HOME/.colima" ]]; then
            log_info "Removing Colima directory manually..."
            rm -rf "$HOME/.colima" 2>/dev/null || true
            log_success "Manually cleaned up Colima directory"
        fi
    fi
else
    log_info "No Colima VM found"
fi

# Clean up Nix configuration
log_info "Cleaning up Nix remote builder configuration..."
NIX_CONF_FILE="$HOME/.config/nix/nix.conf"
if [[ -f "$NIX_CONF_FILE" ]]; then
    if grep -q "ssh://.*aarch64-linux" "$NIX_CONF_FILE"; then
        grep -v "ssh://.*aarch64-linux" "$NIX_CONF_FILE" > "$NIX_CONF_FILE.tmp"
        mv "$NIX_CONF_FILE.tmp" "$NIX_CONF_FILE"
        log_success "Removed remote builder from Nix configuration"
    else
        log_info "No remote builder configuration found in Nix config"
    fi
else
    log_info "No Nix configuration file found"
fi

echo ""
log_success "Cleanup complete!"
echo ""
log_info "To set up the remote builder again, run:"
log_info "  ./builder/setup-remote-builder.sh"
echo ""
log_info "Or use the one-step build command:"
log_info "  nix develop ./builder -c ./builder/make-image.sh"