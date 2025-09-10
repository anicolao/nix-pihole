# Remote Builder for Pi-hole NixOS Images

This directory contains scripts to set up and use a remote builder for building aarch64-linux NixOS images on macOS using Colima.

## Overview

The remote builder setup uses:
- **Colima**: Lightweight container runtime for macOS with aarch64 VM support
- **Docker**: Container runtime managed by Colima
- **NixOS container**: Acts as the remote builder with full Nix environment
- **SSH**: Secure connection to the remote builder

## Quick Start

1. **Enter the development shell**:
   ```bash
   nix develop
   ```

2. **Set up the remote builder**:
   ```bash
   ./builder/setup-remote-builder.sh
   ```

3. **Test the remote builder**:
   ```bash
   ./builder/test-remote-builder.sh
   ```

4. **Build the Pi-hole image**:
   ```bash
   ./builder/make-image.sh
   ```

## Scripts

### `setup-remote-builder.sh`

Sets up the complete remote builder environment:
- Creates a Colima profile with aarch64 architecture
- Launches a NixOS Docker container with Nix daemon
- Configures SSH access with key-based authentication
- Sets up Nix remote builder configuration

**Usage**: `./builder/setup-remote-builder.sh`

### `test-remote-builder.sh`

Tests all components of the remote builder setup:
- Verifies Colima profile is running
- Tests Docker connectivity
- Checks NixOS container status
- Tests SSH connection and Nix functionality
- Performs a simple build test

**Usage**: `./builder/test-remote-builder.sh`

### `make-image.sh`

Builds the Pi-hole RPi4 image using the remote builder:
- Validates remote builder setup
- Starts necessary services if stopped
- Builds the complete NixOS image for aarch64-linux
- Provides timing and result information

**Usage**: `./builder/make-image.sh`

## Configuration

### Colima Profile
- **Name**: `nix-builder`
- **Architecture**: `aarch64`
- **Memory**: `4GB`
- **Disk**: `20GB`
- **CPU**: `4 cores`

### NixOS Container
- **Name**: `nix-remote-builder`
- **Platform**: `linux/arm64`
- **SSH Port**: `2222`
- **Nix Store**: Persistent volume

### SSH Configuration
- **Key**: `~/.ssh/nix-builder` (generated automatically)
- **Host**: `localhost:2222`
- **User**: `root`

## Requirements

All requirements are provided by the `nix develop` shell:
- `colima` - Container runtime for macOS
- `docker` - Container management
- `nix` - Nix package manager
- `openssh` - SSH client
- `coreutils`, `curl`, `jq` - Utilities

## Troubleshooting

### Common Issues

1. **Colima not starting**:
   ```bash
   # Check if another Docker service is running
   ps aux | grep docker
   # Stop other Docker services and try again
   ```

2. **SSH connection fails**:
   ```bash
   # Check container logs
   docker logs nix-remote-builder
   
   # Restart container
   docker restart nix-remote-builder
   ```

3. **Build fails**:
   ```bash
   # Test remote builder
   ./builder/test-remote-builder.sh
   
   # Check Nix configuration
   cat ~/.config/nix/nix.conf
   ```

### Manual Commands

Start Colima profile:
```bash
colima start nix-builder
```

Start NixOS container:
```bash
export DOCKER_HOST="unix://$HOME/.colima/nix-builder/docker.sock"
docker start nix-remote-builder
```

Test SSH connection:
```bash
ssh -i ~/.ssh/nix-builder -p 2222 root@localhost
```

Manual build command:
```bash
nix build .#images.rpi4 --builders "ssh://root@localhost:2222 aarch64-linux ~/.ssh/nix-builder 4 1 nixos-test,benchmark,big-parallel,kvm"
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   macOS Host                    │
│  ┌─────────────────────────────────────────────┐│
│  │              Nix Development Shell          ││
│  │  ┌─────────────────────────────────────────┐││
│  │  │            Colima VM                    │││
│  │  │                                         │││
│  │  │  ┌─────────────────────────────────────┐│││
│  │  │  │        NixOS Container              ││││
│  │  │  │  - aarch64-linux                    ││││
│  │  │  │  - Nix daemon                       ││││
│  │  │  │  - SSH server (port 2222)           ││││
│  │  │  │  - Remote builder                   ││││
│  │  │  └─────────────────────────────────────┘│││
│  │  └─────────────────────────────────────────┘││
│  └─────────────────────────────────────────────┘│
└─────────────────────────────────────────────────┘
         │
         │ SSH (localhost:2222)
         │
    ┌─────────┐
    │ nix     │ ──builds──▶ Pi-hole aarch64-linux image
    │ build   │
    └─────────┘
```

## Performance

**Typical build times**:
- First build: 20-30 minutes (downloads and builds everything)
- Incremental builds: 5-15 minutes (reuses cached components)
- Simple changes: 2-5 minutes

**Resource usage**:
- Memory: ~4GB (allocated to Colima VM)
- Disk: ~10-15GB (Nix store and container images)
- Network: Moderate (downloading packages and dependencies)

## Security

- SSH key-based authentication (no passwords)
- Container isolation within Colima VM
- Local-only connections (localhost:2222)
- Nix store integrity verification
- Reproducible builds

## Integration

The remote builder integrates with:
- Standard Nix commands (`nix build`, `nix develop`)
- Existing flake.nix configuration
- Personal configuration in `personal/` directory
- Emulation frameworks in `emu/` and `emu2/`

## Maintenance

**Regular maintenance**:
```bash
# Update Colima
brew upgrade colima

# Clean up Docker resources
docker system prune

# Update Nix packages in container
ssh -i ~/.ssh/nix-builder -p 2222 root@localhost "nix-channel --update"
```

**Reset everything**:
```bash
# Stop and remove everything
colima stop nix-builder
colima delete nix-builder
docker system prune -af

# Start fresh
./builder/setup-remote-builder.sh
```