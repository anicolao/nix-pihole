#!/usr/bin/env bash
set -euo pipefail

echo "Building the RPi4 image using the remote builder..."

export NIX_SSHOPTS="-p 30022"
export SSHPASS="nixos"

# The remote builder machine details
REMOTE_BUILDER="ssh://nixos@localhost"
REMOTE_SYSTEM="aarch64-linux"

# Build the RPi4 image from the parent directory's flake
sshpass -e nix build path:$PWD/..#images.rpi4 --system "$REMOTE_SYSTEM" --extra-experimental-features "nix-command flakes" --builder "$REMOTE_BUILDER"

echo "RPi4 image build completed successfully."
echo "The image is available in the 'result' directory in the parent folder."
