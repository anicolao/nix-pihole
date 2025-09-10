#!/usr/bin/env bash
set -euo pipefail

echo "--> Testing the remote builder connection..."

# These environment variables are used by Nix for SSH connections.
export NIX_SSHOPTS="-p 30022"
# The password is 'nixos' as set in builder.nix.
export SSHPASS="nixos"

# The remote builder machine details.
REMOTE_BUILDER="ssh://nixos@localhost"
REMOTE_SYSTEM="aarch64-linux"

# Test building a simple package for aarch64-linux.
# We use sshpass to provide the password non-interactively.
sshpass -e nix build nixpkgs#hello --system "$REMOTE_SYSTEM" --extra-experimental-features "nix-command flakes" --builder "$REMOTE_BUILDER"

echo
echo "✅ Remote builder test completed successfully."
