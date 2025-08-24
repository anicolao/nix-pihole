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

The builder solution uses a simplified approach that leverages existing Docker images:

**Alpine Linux + Nix Image** - Uses the official `nixos/nix:latest` Docker image which provides:
- Pre-installed Nix package manager on Alpine Linux base
- Standard Alpine package management (apk) for reliable SSH server installation  
- Eliminates complex Nix installation and privilege separation issues
- Uses declarative Alpine package management instead of manual SSH configuration

This approach avoids the previous complexity of:
- Installing Nix from scratch in containers (which often failed due to network or dependency issues)
- Manual SSH daemon configuration with privilege separation setup
- Complex systemd-based container setups that caused "failed to create task" errors

### Technical Details

The setup process:
1. Uses `nixos/nix:latest` image with Nix already installed on Alpine Linux
2. Installs SSH server via Alpine's `apk` package manager (much more reliable than manual setup)
3. Configures SSH using standard configuration files and Alpine's service management
4. Sets up SSH keys for remote access
5. Configures Nix for remote building with proper settings

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