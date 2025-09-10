#!/usr/bin/env bash
set -euo pipefail

echo "--> Building the RPi4 image using the remote builder..."

# These environment variables are used by Nix for SSH connections.
export NIX_SSHOPTS="-p 30022"
# The password is 'nixos' as set in builder.nix.
export SSHPASS="nixos"

# The remote builder machine details.
REMOTE_BUILDER="ssh://nixos@localhost"

# Build the RPi4 image from the parent directory's flake.
# We use sshpass to provide the password non-interactively.
# Note: The system is implicitly aarch64-linux because that's what the flake in the parent dir specifies.
sshpass -e nix build path:$PWD/..#images.rpi4 --extra-experimental-features "nix-command flakes" --builder "$REMOTE_BUILDER"

echo
echo "✅ RPi4 image build completed successfully."
echo "The image is available in the 'result' directory in the parent folder."
