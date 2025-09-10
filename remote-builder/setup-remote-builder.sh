#!/usr/bin/env bash
set -euo pipefail

echo "Setting up the remote builder..."

# 1. Start Colima
echo "Starting Colima VM..."
if ! colima status remote-builder &>/dev/null; then
  colima start remote-builder --arch aarch64 --memory 4 --disk 20
else
  echo "Colima VM 'remote-builder' is already running."
fi

# 2. Start Nix daemon container
echo "Starting Nix daemon container..."
if ! docker ps --filter "name=nix-remote-builder" --format "{{.Names}}" | grep -q "nix-remote-builder"; then
  echo "Starting Nix daemon container with SSH..."
  # We need to run sshd in the foreground to keep the container alive.
  # We need to find the absolute path to sshd inside the container and use that,
  # as sshd refuses to start otherwise. 'which' will find it in the $PATH.
  # We use 'sh -c' to execute this command inside the container, and 'exec'
  # to make sshd the main process, which is important for signal handling.
  docker run -d --name nix-remote-builder \
    -v nix-store:/nix/store \
    -p 30022:22 \
    nixos/nix:latest sh -c 'exec $(which sshd) -D -e'
  echo "Nix daemon container started."
else
  echo "Nix daemon container is already running."
fi

echo "Remote builder setup is complete."
echo "You can now use the remote builder."
