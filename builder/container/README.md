# Nix Remote Builder Docker Container

This directory contains the Nix configuration to build a Docker image pre-configured as a remote builder for cross-compilation.

## Overview

Instead of manually setting up SSH and Nix in a running container, this approach uses Nix to declaratively build a Docker image that comes with everything pre-configured:

- NixOS environment with Nix package manager
- SSH server properly configured for remote access
- All required system users and directories
- Nix configuration optimized for remote building

## Building the Image

```bash
# Build the Docker image
./build-image.sh

# Or manually:
nix build .#nix-remote-builder
docker load < result
```

**Note**: If you encounter `derivationStrict` errors, ensure you're using a recent version with the simplified Docker image configuration that avoids complex package dependencies and privilege separation issues.

## Using the Image

The built image can be used as a drop-in replacement for manual container setup:

```bash
# Run the container
docker run -d --name nix-remote-builder -p 2222:22 nix-remote-builder:latest

# Add your SSH public key
docker cp ~/.ssh/nix-remote-builder.pub nix-remote-builder:/root/.ssh/authorized_keys

# Test SSH connection
ssh -i ~/.ssh/nix-remote-builder -p 2222 root@localhost
```

## Advantages

- **Reproducible**: Every container starts with identical configuration
- **Fast startup**: No runtime installation or configuration needed
- **Reliable**: Eliminates manual setup failures and SSH configuration issues
- **Declarative**: All configuration is defined in Nix files
- **Debuggable**: Easy to modify and rebuild if changes are needed

## Integration

This pre-built image integrates with the existing builder scripts by replacing the manual container setup in `setup-remote-builder.sh` with a simple `docker run` command using this image.

## Files

- `flake.nix` - Nix configuration to build the Docker image
- `build-image.sh` - Script to build and load the image
- `README.md` - This documentation