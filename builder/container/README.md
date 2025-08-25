# Nix Remote Builder Docker Container

This directory contains the Nix configuration to build a Docker image pre-configured as a remote builder for cross-compilation.

## Overview

This approach uses canonical NixOS configuration patterns to build a Docker image that comes with everything pre-configured:

- SSH server configured using NixOS `services.openssh` canonical approach
- Nix package manager optimized for remote building
- All required system users and directories
- Proper SSH security settings following NixOS best practices

## Key Features

**Canonical NixOS SSH Configuration**: Instead of manually writing SSH daemon configuration files, this container uses the standard NixOS `services.openssh` module approach to generate proper SSH configuration. This ensures:

- SSH settings follow NixOS security best practices
- Configuration is maintainable and consistent with NixOS systems
- Proper host key generation and management
- Standard authentication and security policies

## Building the Image

```bash
# Build the Docker image using Nix
nix build .#nix-remote-builder
docker load < result

# Or using the build script:
../build-image.sh
```

## SSH Configuration Approach

The container now uses the canonical NixOS approach for SSH configuration:

```nix
# In flake.nix - SSH configured the NixOS way
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "yes";
    PubkeyAuthentication = true;
    PasswordAuthentication = false;
    UsePAM = false;
    StrictModes = true;
  };
  hostKeys = [
    { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
    { path = "/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
    { path = "/etc/ssh/ssh_host_ecdsa_key"; type = "ecdsa"; bits = 521; }
  ];
};
```

This replaces manual `sshd_config` creation with NixOS's standard service configuration.

## Using the Image

```bash
# Run the container
docker run -d --name nix-remote-builder -p 2222:22 nix-remote-builder:latest

# Add your SSH public key
docker cp ~/.ssh/nix-remote-builder.pub nix-remote-builder:/root/.ssh/authorized_keys

# Test SSH connection
ssh -i ~/.ssh/nix-remote-builder -p 2222 root@localhost
```

## Advantages

- **NixOS Best Practices**: Uses canonical NixOS service configuration patterns
- **Maintainable**: SSH configuration follows standard NixOS module structure
- **Secure**: Implements NixOS security defaults for SSH
- **Reproducible**: Every container starts with identical configuration
- **Fast startup**: No runtime installation or configuration needed
- **Declarative**: All configuration is defined in Nix files using standard patterns

## Files

- `flake.nix` - Nix configuration using canonical NixOS SSH service patterns
- `build-image.sh` - Script to build and load the image
- `README.md` - This documentation