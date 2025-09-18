# Pi 3B+ Support Example

This document demonstrates building and emulating Pi 3B+ images with the newly added support.

## Quick Start

### 1. Build the Pi 3B+ Image
First, build the SD card image using Nix.
```bash
# Build the Pi 3B+ image
nix build .#images.rpi3bplus

# The built image will be available in result/sd-image/
ls result/sd-image/nixos-sd-image-*.img
```

### 2. Prepare and Resize the Image for Emulation
The raw image produced by the build is small. For emulation, it's better to resize it to a more realistic size, like 8GB.

**Note**: The `images/` directory is git-ignored to store large image files.

```bash
# Create a directory to store the resized image
mkdir -p images

# Identify the source image path
SOURCE_IMAGE=$(ls result/sd-image/nixos-sd-image-*.img | head -n 1)

# Resize the image to 8GB using qemu-img
qemu-img resize -f raw "$SOURCE_IMAGE" 8G

# Move the resized image to the images/ directory
mv "$SOURCE_IMAGE" images/nixos-pi3-8g.img
```

### 3. Test with Emulation
Now, launch the resized image using the QEMU emulation script. You must specify `--pi3` for Pi 3 emulation.

```bash
# Navigate to the emulation directory and enter the Nix shell
cd emu/
nix develop

# Launch the resized image
./launch-pi.sh --pi3 ../images/nixos-pi3-8g.img
```

### 4. Flash to Real Hardware
When flashing to a physical SD card, use the **original** (non-resized) image from the `result/` directory.

```bash
# Flash the original image to an SD card
sudo dd if=$(ls result/sd-image/nixos-sd-image-*.img | head -n 1) of=/dev/sdX bs=4M status=progress
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