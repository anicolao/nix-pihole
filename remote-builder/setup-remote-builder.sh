#!/usr/bin/env bash
set -euo pipefail

echo "Setting up the remote builder..."

# --- Step 1: Start Colima ---
echo "--> Ensuring Colima VM is running..."
if ! colima status remote-builder &>/dev/null; then
  colima start remote-builder --arch aarch64 --memory 4 --disk 20
else
  echo "    Colima VM 'remote-builder' is already running."
fi

# --- Step 2: Build the custom Docker image ---
echo "--> Building the NixOS-based builder Docker image..."
# This command builds the image defined in our flake.nix and creates a symlink to the result.
# We use a specific name for the symlink to avoid conflicts.
nix build .#packages.aarch64-linux.builder-image --out-link ./result-builder-image

# --- Step 3: Load the image into Docker ---
echo "--> Loading the builder image into Docker..."
docker load < ./result-builder-image
rm ./result-builder-image # Clean up the symlink

# --- Step 4: Stop and remove any old container ---
echo "--> Stopping and removing any existing builder container..."
docker stop nix-remote-builder &>/dev/null || true
docker rm nix-remote-builder &>/dev/null || true

# --- Step 5: Run the new container ---
echo "--> Starting the new builder container..."
# The image is named 'nixos-remote-builder:latest' as defined in builder.nix
docker run -d --name nix-remote-builder -p 30022:22 nixos-remote-builder:latest

echo
echo "✅ Remote builder setup is complete."
echo "You can now test the connection with './test-remote-builder.sh'"
echo "or build the main project image with './make-image.sh'"
