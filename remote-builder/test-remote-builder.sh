#!/usr/bin/env bash
set -euo pipefail

echo "Testing the remote builder..."

export NIX_SSHOPTS="-p 30022"
export SSHPASS="nixos"

# The remote builder machine details
REMOTE_BUILDER="ssh://nixos@localhost"
REMOTE_SYSTEM="aarch64-linux"

# Test building a simple package for aarch64-linux
sshpass -e nix build nixpkgs#hello --system "$REMOTE_SYSTEM" --extra-experimental-features "nix-command flakes" --builder "$REMOTE_BUILDER"

echo "Remote builder test completed successfully."
