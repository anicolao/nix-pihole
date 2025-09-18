# Pi 3B+ Support Example

This document demonstrates building and emulating Pi 3B+ images with the newly added support.

## Quick Start

### 1. Build Pi 3B+ Image
```bash
# Build the Pi 3B+ image
nix build .#images.rpi3bplus

# The built image will be in result/sd-image/
ls result/sd-image/nixos-sd-image-*.img
```

### 2. Test with Emulation
```bash
# Option A: Using emu/ with Pi 3 fallback
cd emu/
nix develop
./launch-pi.sh --pi3 ../result/sd-image/nixos-sd-image-*.img

# Option B: Using emu2/ with direct boot
cd emu2/
nix develop  
./launch-direct.sh ../result/sd-image/nixos-sd-image-*.img
```

### 3. Flash to Real Hardware
```bash
# Flash to SD card for real Pi 3B+ hardware
sudo dd if=result/sd-image/nixos-sd-image-*.img of=/dev/sdX bs=4M status=progress
```

## Build Commands Summary

| Target | Command | Description |
|--------|---------|-------------|
| Pi 4 | `nix build .#images.rpi4` | Raspberry Pi 4 image |
| Pi 3B+ | `nix build .#images.rpi3bplus` | Raspberry Pi 3B+ image |

Both images use identical NixOS configuration and modules - the only difference is the target name for clarity.

## Hardware Compatibility

The same NixOS configuration works on both Pi 3B+ and Pi 4 because:
- Both use AArch64 (64-bit ARM) architecture
- NixOS uses generic AArch64 SD card image module
- Hardware-specific drivers are detected at boot time
- Same software packages are compatible with both platforms