# Raspberry Pi 4 Emulator

This directory contains a reproducible Raspberry Pi 4 emulation environment using Nix and QEMU.

## Quick Start

1. **Enter the Nix development shell:**
   ```bash
   nix develop
   ```

2. **Launch the emulator:**
   ```bash
   ./launch-pi.sh /path/to/your/raspios-image.img
   ```

3. **Connect via SSH (once booted):**
   ```bash
   ssh pi@localhost -p 5022
   ```

## Files

- **`flake.nix`** - Nix flake that provides QEMU and required tools
- **`launch-pi.sh`** - Cross-platform script to launch the Pi 4 emulator
- **`setup-remote-builder.sh`** - Script to set up remote builder for cross-compilation on macOS
- **`build-with-remote.sh`** - Convenience script to build with automatic remote builder setup
- **`test-remote-builder.sh`** - Test script to validate remote builder functionality
- **`README.md`** - This file

## Features

### Cross-Platform Support
The emulator works on both Linux and macOS:
- **Linux**: Uses loop devices and mount for image access
- **macOS**: Uses hdiutil for image mounting

### Command Line Options
```bash
./launch-pi.sh [OPTIONS] /path/to/raspberry-pi.img

OPTIONS:
    --help          Show help message
    --pi3           Use Pi 3 fallback for better stability
    --port PORT     Custom SSH forward port (default: 5022)
    --dry-run       Show QEMU command without executing
```

### Examples
```bash
# Basic usage
./launch-pi.sh raspios-lite.img

# Use Pi 3 emulation for stability
./launch-pi.sh --pi3 raspios-lite.img

# Custom SSH port
./launch-pi.sh --port 2222 raspios-lite.img

# See what command would be run
./launch-pi.sh --dry-run raspios-lite.img
```

## Requirements

- A Raspberry Pi OS image file (`.img`)
- Nix package manager
- On Linux: sudo access for mounting images

## Troubleshooting

### Pi 4 vs Pi 3 Emulation
If you experience instability with Pi 4 emulation, use the `--pi3` flag for more stable Pi 3 emulation with Pi 4 CPU performance.

### Image Mounting Issues
- **Linux**: Ensure you have sudo access and loop device support
- **macOS**: Ensure the image is a raw disk image (not compressed)

### Network Connectivity
The emulator uses QEMU's user networking with SSH forwarding. The Pi should get an IP address automatically via DHCP.

## Testing Without an Image

You can test the script setup without a real image:

```bash
# Check if the environment is working
./test-emu.sh
```

This will validate that QEMU is available and the script parses arguments correctly.

## Remote Builder Setup for Cross-Compilation (macOS)

If you encounter issues building the Raspberry Pi image on macOS due to cross-compilation problems, use the remote builder setup:

```bash
# Set up a remote builder using Colima (requires Docker and Colima)
./setup-remote-builder.sh
```

This script will:
1. **Start Colima** with aarch64 support
2. **Create a NixOS container** with SSH access
3. **Configure Nix** to use the container as a remote builder
4. **Test the connection** to ensure everything works

After running the script, you can build Raspberry Pi images from your Mac:

```bash
# Navigate to the project root and build
cd ..
nix build path:$PWD#images.rpi4
```

### Remote Builder Management

```bash
# Test the remote builder setup
./test-remote-builder.sh

# Stop the remote builder when done
docker stop nix-remote-builder

# Restart the remote builder later
./setup-remote-builder.sh

# Remove the remote builder completely
docker stop nix-remote-builder
docker rm nix-remote-builder
```

The remote builder approach is more reliable than direct cross-compilation and works around limitations in cross-compiling NixOS systems from macOS.