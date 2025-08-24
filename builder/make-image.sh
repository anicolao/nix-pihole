#!/usr/bin/env bash
#
# make-image.sh - Build RPi4 image using Colima remote builder
#
# This script automatically sets up a Colima-based remote builder and builds
# the Pi-hole RPi4 image for cross-compilation from macOS to aarch64-linux.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configure Docker to use Colima
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

echo "Pi-hole RPi4 Image Builder" >&2
echo "=========================" >&2
echo >&2

# Check if we're in the right directory
if [[ ! -f "$PROJECT_ROOT/flake.nix" ]]; then
    echo "Error: Could not find project flake.nix. Please run from project root or builder directory." >&2
    exit 1
fi

# Check if colima and docker are available
if ! command -v colima >/dev/null 2>&1; then
    echo "Error: colima is not installed. Please install it with:" >&2
    echo "  brew install colima" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed. Please install it with:" >&2
    echo "  brew install docker" >&2
    exit 1
fi

echo "Setting up remote builder..." >&2
"$SCRIPT_DIR/setup-remote-builder.sh"

echo >&2
echo "Building RPi4 image..." >&2
cd "$PROJECT_ROOT"

# Try to build the image using the remote builder
if nix build path:$PWD#images.rpi4; then
    echo >&2
    echo "✅ Build successful!" >&2
    echo "Image available at: $(readlink -f result)" >&2
    
    # Show image info
    if [[ -f "result" ]]; then
        echo >&2
        echo "Image details:" >&2
        ls -lh result >&2
    fi
else
    echo >&2
    echo "❌ Build failed!" >&2
    echo "You can try running the test script to diagnose issues:" >&2
    echo "  $SCRIPT_DIR/test-remote-builder.sh" >&2
    exit 1
fi