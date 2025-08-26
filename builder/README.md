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

The builder solution uses a **pre-built Docker image approach** for maximum reliability:

**Pre-built nixos/nix Image** - Uses the official `nixos/nix:latest` Docker image which includes:
- Alpine Linux base with Nix package manager pre-installed
- Minimal, reliable foundation for SSH server installation
- Standard Alpine package management (apk) for additional dependencies
- No complex systemd or NixOS module dependencies

**Runtime SSH Configuration** - The setup script then:
- Installs OpenSSH server using Alpine's package manager
- Generates SSH host keys and configures authentication
- Ensures root account is unlocked for SSH key authentication
- Starts SSH daemon and verifies connectivity

This approach eliminates the previous complexity of:
- Complex NixOS module evaluation in Docker containers
- File collisions between custom SSH configs and openssh packages
- Cross-compilation issues in Docker image builds
- Container startup failures due to systemd dependencies

### Technical Details

The setup process:
1. **Pre-built Image**: Uses the official `nixos/nix:latest` Docker image
2. **SSH Installation**: Installs OpenSSH using Alpine package manager (apk)
3. **Root Account Setup**: Ensures root account is unlocked for SSH key authentication
4. **SSH Configuration**: Configures SSH for key-based authentication
5. **Remote Builder**: Configures Nix to use the container as a remote builder

## Architecture

```
Host (macOS)          Container (aarch64-linux)
├── Nix (client)  ->  ├── Nix (builder)
├── SSH client    ->  ├── SSH server (pre-configured)
└── Docker        ->  └── Pre-built image with everything ready
```

## Files

- `flake.nix` - Nix development environment with required dependencies (colima, docker, etc.)
- `make-image.sh` - Main entry point script for building the RPi4 image
- `setup-remote-builder.sh` - Sets up the remote builder using pre-built Docker image
- `test-remote-builder.sh` - Tests the remote builder functionality
- `cleanup.sh` - Cleans up Colima and Docker containers
- `container/` - **NEW**: Directory containing Nix configuration to build the Docker image
  - `container/flake.nix` - Nix configuration for building the Docker image
  - `container/build-image.sh` - Script to build and load the Docker image
  - `container/README.md` - Documentation for the container build process
- `cleanup.sh` - Cleans up Docker containers and Colima instances
- `remote-builder-config.nix` - NixOS configuration for the remote builder container
- `remote-builder-flake.nix` - Flake for building the NixOS Docker image
- `README.md` - This file

## Troubleshooting

### Docker Image Issues
If you encounter "unable to find user root" or other Docker image issues, the problem may be an outdated or corrupted Docker image. The cleanup script now removes Docker images as well as containers:

```bash
# Complete cleanup including Docker images
./builder/cleanup.sh

# Force rebuild of Docker image
nix develop ./builder -c ./builder/make-image.sh --force-rebuild

# Or just the setup with force rebuild
./builder/setup-remote-builder.sh --force-rebuild
```

### Docker Connection Issues
The scripts automatically configure `DOCKER_HOST` to connect to Colima. If you see Docker connection errors, ensure Colima is running:

```bash
colima status
```

### Container Build Failures
If the NixOS image build fails, the system will automatically detect and rebuild corrupted images. You can also force a clean rebuild:

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