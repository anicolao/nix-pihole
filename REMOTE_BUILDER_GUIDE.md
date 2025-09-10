# Remote Builder Quick Start Guide

This guide walks you through setting up and using the remote builder to create Pi-hole NixOS images on macOS.

## What is the Remote Builder?

The remote builder allows you to build aarch64-linux (ARM64) NixOS images on macOS by using:
- **Colima**: Lightweight container runtime with ARM64 VM support
- **NixOS Container**: Full Nix environment running in ARM64 mode  
- **SSH Remote Building**: Nix's built-in remote builder capability

This enables native ARM64 compilation without requiring actual ARM64 hardware.

## Prerequisites

- macOS with Apple Silicon or Intel Mac
- Nix package manager installed
- Git (for cloning the repository)

## Step-by-Step Setup

### 1. Clone and Enter the Repository

```bash
git clone https://github.com/anicolao/nix-pihole.git
cd nix-pihole
```

### 2. Enter the Development Environment

```bash
nix develop
```

This will:
- Install all required tools (colima, docker, nix, etc.)
- Set up the environment variables  
- Display available commands

### 3. Set Up the Remote Builder (One-time)

```bash
./builder/setup-remote-builder.sh
```

This script will:
- Create a Colima VM profile named "nix-builder"
- Launch an ARM64 VM with 4GB RAM and 20GB disk
- Set up a NixOS container with Nix daemon
- Configure SSH access with automatic key generation
- Set up Nix remote builder configuration

**Expected time**: 5-10 minutes

### 4. Test the Remote Builder

```bash
./builder/test-remote-builder.sh
```

This verifies:
- Colima profile is running
- Docker connectivity works
- NixOS container is accessible
- SSH connection functions
- Nix can build packages

### 5. Build the Pi-hole Image

```bash
./builder/make-image.sh
```

This will:
- Validate the remote builder setup
- Build the complete NixOS Pi-hole image for Raspberry Pi 4
- Use the remote ARM64 builder for native compilation
- Provide timing and result information

**Expected time**: 15-30 minutes (first build), 5-15 minutes (subsequent builds)

## What You Get

After a successful build, you'll have:
- A complete NixOS SD card image (`result/sd-image/*.img`)
- Ready to flash to a Raspberry Pi 4
- Includes Pi-hole DNS filtering
- SSH access configured
- All necessary drivers and configurations

## Common Commands

### Start/Stop the Remote Builder

```bash
# Start (if stopped)
colima start nix-builder

# Stop (to save resources)
colima stop nix-builder

# Status
colima status nix-builder
```

### Flash the Image to SD Card

```bash
# Find your SD card device (be careful!)
diskutil list

# Flash the image (replace /dev/diskX with your SD card)
sudo dd if=result/sd-image/*.img of=/dev/diskX bs=4M status=progress
```

### Test in Emulator Instead

```bash
cd emu2
./demo-integration.sh
```

## Troubleshooting

### Remote Builder Won't Start
```bash
# Check Colima status
colima list

# Restart Colima
colima stop nix-builder
colima start nix-builder

# Check Docker
docker ps
```

### Build Fails
```bash
# Test the remote builder
./builder/test-remote-builder.sh

# Check container logs
docker logs nix-remote-builder

# Reset everything
colima delete nix-builder
./builder/setup-remote-builder.sh
```

### SSH Connection Issues
```bash
# Test SSH manually
ssh -i ~/.ssh/nix-builder -p 2222 root@localhost

# Check SSH key
ls -la ~/.ssh/nix-builder*

# Regenerate if needed (will be done by setup script)
```

## Advanced Usage

### Custom Build Targets

You can build other targets from the flake:

```bash
# Build just the NixOS configuration
nix build .#nixosConfigurations.rpi4.config.system.build.toplevel --builders "ssh://root@localhost:2222"

# Build with custom configuration
nix build .#packages.aarch64-linux.nixosConfigurations.pihole --builders "ssh://root@localhost:2222"
```

### Resource Adjustment

Edit the configuration in `builder/setup-remote-builder.sh`:

```bash
COLIMA_MEMORY="8GB"    # Increase for faster builds
COLIMA_DISK="40GB"     # More space for Nix store
COLIMA_CPU="8"         # More CPU cores
```

Then recreate the profile:
```bash
colima delete nix-builder
./builder/setup-remote-builder.sh
```

## Why This Approach?

**Benefits:**
- ✅ Native ARM64 compilation (faster, more compatible)
- ✅ Uses Apple Silicon efficiently (if available)
- ✅ Lightweight (compared to full VM solutions)
- ✅ Persistent Nix store (caching across builds)
- ✅ Standard Nix workflow (works with any Nix project)

**Compared to alternatives:**
- **Better than QEMU emulation**: Much faster, native execution
- **Better than GitHub Actions**: Local builds, no CI/CD needed
- **Better than Docker Desktop**: Lighter weight, purpose-built for ARM64

## Next Steps

Once you have a working image:

1. **Flash to Raspberry Pi 4**: Use the built SD card image
2. **Configure networking**: Set up WiFi or ethernet
3. **Access Pi-hole**: Web interface on port 8080
4. **Set up DNS**: Point your router to the Pi's IP address

See the main README.md for complete setup and configuration instructions.