# Pi 3B+ Support Example

This document demonstrates building and emulating Pi 3B+ images with the newly
added support.

## Quick Start

### 1. Build the Pi Image (works on both Pi 3B+ and Pi 4)

First, build the SD card image using Nix.

```bash
# Build the Pi 3B+ image
nix build .#images.pihole

# The built image will be available in result/sd-image/
ls result/sd-image/
```

### 2. Prepare and Resize the Image for Emulation

The raw image produced by the build is small. QEMU requires a power of 2 size,
so resize it to a usable size, like 8GB.

```bash
# Create a directory to store the resized image
mkdir -p ../images

# Identify the source image path
SOURCE_IMAGE=$(ls result/sd-image/*-image-*.img | head -n 1)

# Move the resized image to the ../images/ directory
cp "$SOURCE_IMAGE" ../images/nixos-pi3-8g.img
chmod +w ../images/nixos-pi3-8g.img

# Resize the image to 8GB using qemu-img
nix develop ./emu -c qemu-img resize -f raw ../images/nixos-pi3-8g.img 8G
```

### 3. Test with Emulation

Now, launch the resized image using the QEMU emulation script. You must specify
`--pi3` for Pi 3 emulation.

```bash
# Launch the resized image
nix develop ./emu -c ./emu/launch-pi.sh --pi3 ../images/nixos-pi3-8g.img
```

### 4. Flash to Real Hardware

When flashing to a physical SD card, use the **original** (non-resized) image
from the `result/` directory.

```bash
# Flash the original image to an SD card
sudo dd if=$SOURCE_IMAGE of=/dev/sdX bs=4M status=progress
```

## Hardware Compatibility

The same NixOS configuration works on both Pi 3B+ and Pi 4 because:

- Both use AArch64 (64-bit ARM) architecture
- NixOS uses generic AArch64 SD card image module
- Hardware-specific drivers are detected at boot time
- Same software packages are compatible with both platforms
