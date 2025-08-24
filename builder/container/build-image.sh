#!/usr/bin/env bash
set -euo pipefail

# Build the Docker image using Nix
# This script builds a Docker image that includes:
# - NixOS environment
# - SSH server pre-configured
# - Nix package manager ready for remote building

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

main() {
    log_info "Building Nix remote builder Docker image..."
    
    # Change to the container directory
    cd "$SCRIPT_DIR"
    
    # Build the Docker image using Nix
    log_info "Building Docker image with Nix (this may take a few minutes)..."
    if nix build .#nix-remote-builder; then
        log_success "Docker image built successfully"
    else
        log_error "Failed to build Docker image"
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available. Please ensure Docker is installed and running."
        exit 1
    fi
    
    # Load the image into Docker
    log_info "Loading Docker image into Docker daemon..."
    if docker load < result; then
        log_success "Docker image loaded successfully"
    else
        log_error "Failed to load Docker image into Docker"
        exit 1
    fi
    
    # Show the loaded image
    log_info "Docker image details:"
    docker images nix-remote-builder:latest
    
    log_success "Docker image 'nix-remote-builder:latest' is ready!"
    echo ""
    log_info "Next steps:"
    echo "1. Use this image in your builder scripts instead of manual SSH setup"
    echo "2. Run with: docker run -d --name nix-remote-builder -p 2222:22 nix-remote-builder:latest"
    echo "3. Add your SSH public key to the container's authorized_keys"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi