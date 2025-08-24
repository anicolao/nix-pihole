#!/usr/bin/env bash
set -euo pipefail

# Convenience script to build Raspberry Pi 4 image with remote builder on macOS
# This script sets up a remote builder if needed and then builds the image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

main() {
    log_info "Building Raspberry Pi 4 image with remote builder..."
    
    # Check if we're on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        log_info "Detected macOS - setting up remote builder..."
        
        # Run the remote builder setup script
        "$SCRIPT_DIR/setup-remote-builder.sh"
        
        log_info "Remote builder ready, starting build..."
    else
        log_info "Non-macOS platform detected, attempting direct build..."
    fi
    
    # Navigate to project root and build
    cd "$PROJECT_ROOT"
    
    log_info "Building image with: nix build path:\$PWD#images.rpi4"
    nix build "path:$PWD#images.rpi4"
    
    log_success "Build complete!"
    log_info "Image location: $PROJECT_ROOT/result/sd-image/"
    ls -la "$PROJECT_ROOT/result/sd-image/"*.img 2>/dev/null || {
        log_info "Image files:"
        find "$PROJECT_ROOT/result" -name "*.img" -exec ls -la {} \;
    }
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi