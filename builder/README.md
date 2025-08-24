# Pi-hole RPi4 Image Builder

This directory contains tools for building Raspberry Pi 4 images using a remote builder approach, specifically designed to work around cross-compilation issues on macOS.

## Quick Start

For macOS users experiencing cross-compilation issues:

```bash
# Install dependencies (one-time setup)
brew install colima docker

# Enter Nix development environment and build in one command
nix develop ./builder -c ./builder/make-image.sh

# If you encounter issues, clean up and try again
./builder/cleanup.sh
nix develop ./builder -c ./builder/make-image.sh
```

## How It Works

The builder solution uses two approaches:

1. **Preferred: NixOS Docker Image** - A proper NixOS configuration creates a Docker image with SSH pre-configured
2. **Fallback: Manual Setup** - If the NixOS image build fails, falls back to manual SSH configuration

### NixOS Docker Image Approach

The preferred approach uses:
- `remote-builder-config.nix` - A proper NixOS configuration for the remote builder container
- `remote-builder-flake.nix` - Nix flake that builds the Docker image declaratively
- Automatically configured SSH service, users, and build environment
- No manual user creation or SSH daemon configuration needed

### Fallback Manual Approach

If the NixOS image approach fails, the system falls back to:
- Using the `nixos/nix:latest` base image
- Manually installing SSH and configuring it
- This is the "hard mode" approach mentioned in feedback, but serves as a reliable fallback

## Files

- `flake.nix` - Nix development environment with required dependencies (colima, docker, etc.)
- `make-image.sh` - Main entry point script for building the RPi4 image
- `setup-remote-builder.sh` - Sets up the remote builder (called by make-image.sh)
- `test-remote-builder.sh` - Tests the remote builder functionality
- `cleanup.sh` - Cleans up Docker containers and Colima instances
- `remote-builder-config.nix` - NixOS configuration for the remote builder container
- `remote-builder-flake.nix` - Flake for building the NixOS Docker image
- `README.md` - This file

## Troubleshooting

### Docker Connection Issues
The scripts automatically configure `DOCKER_HOST` to connect to Colima. If you see Docker connection errors, ensure Colima is running:

```bash
colima status
```

### Container Build Failures
If the NixOS image build fails, the system will fall back to manual setup. You can force a clean rebuild:

```bash
./builder/cleanup.sh
nix develop ./builder -c ./builder/make-image.sh
```

### Disk Space Issues
Colima is configured with a 40GB disk by default. If you need more space, edit the disk size in `setup-remote-builder.sh`:

```bash
colima start --arch aarch64 --cpu 4 --memory 8 --disk 60  # Change 40 to 60
```

### SSH Connection Issues
The setup includes comprehensive SSH connectivity testing. If SSH fails:

1. Check if the container is running: `docker ps | grep nix-remote-builder`
2. Check container logs: `docker logs nix-remote-builder`
3. Test manual SSH: `ssh -i ~/.ssh/nix-remote-builder -p 2222 root@localhost`

## Implementation Details

The remote builder approach provides native aarch64-linux builds instead of cross-compilation, offering a more reliable solution for macOS users while maintaining compatibility with other platforms. The builder integrates with Nix's development environment for a seamless developer experience with comprehensive error handling and troubleshooting tools.

The solution now uses proper NixOS configuration instead of manual setup wherever possible, following Nix best practices and reducing the complexity and fragility of the SSH setup process.