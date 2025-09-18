# Migration Guide: From emu/ to emu2/

This document explains the differences between the original `emu/` and the new `emu2/` emulation frameworks, and how to migrate.

## Why emu2/ was created

The original `emu/` directory had several limitations:

1. **Complex file extraction** - Required mounting SD images and extracting kernel/DTB files
2. **macOS compatibility issues** - Mounting operations were unreliable on macOS
3. **Image assumptions** - Assumed specific image formats and file locations
4. **Not optimized for NixOS** - Designed for generic Raspberry Pi OS images

## Key Differences

| Aspect | emu/ (old) | emu2/ (new) |
|--------|------------|-------------|
| **Boot method** | Extract kernel/DTB files | Direct boot via U-Boot |
| **File operations** | Mount, extract, copy | None required |
| **macOS support** | Unreliable mounting | No mounting needed |
| **Image compatibility** | Generic Raspberry Pi OS | NixOS SD images |
| **Complexity** | High (200+ lines) | Low (150+ lines) |
| **Reliability** | Prone to mounting failures | Robust direct boot |
| **Hardware simulation** | Partial (manual files) | Complete (real boot process) |

## Technical Approach Comparison

### emu/ approach:
```
1. Mount SD image → 2. Extract files → 3. Boot with extracted files
   (Can fail)        (Complex)         (Doesn't match real hardware)
```

### emu2/ approach:
```
1. Direct boot from image (like real hardware)
   (Simple, reliable, authentic)
```

## Migration Steps

If you're currently using `emu/`, here's how to migrate to `emu2/`:

### 1. Switch directories
```bash
# Old way
cd emu/
nix develop

# New way  
cd emu2/
nix develop
```

### 2. Update your workflow
```bash
# Old way (emu/)
./launch-pi.sh raspios-lite.img

# New way (emu2/)
./launch-direct.sh nixos-sd-image-rpi4.img     # For Pi 4
./launch-direct.sh nixos-sd-image-rpi3bplus.img # For Pi 3B+
```

### 3. Build NixOS images instead of using generic ones
```bash
# Build NixOS image from repository root
nix build .#images.rpi4      # For Pi 4
nix build .#images.rpi3bplus # For Pi 3B+

# Use the built image
cd emu2/
./launch-direct.sh ../result/sd-image/nixos-sd-image-*.img
```

### 4. Update any scripts or automation
Replace references to:
- `emu/launch-pi.sh` → `emu2/launch-direct.sh`
- Generic Raspberry Pi OS images → NixOS images built by this repository

## Command Comparison

### Common operations:

| Task | emu/ command | emu2/ command |
|------|-------------|---------------|
| Basic launch | `./launch-pi.sh image.img` | `./launch-direct.sh image.img` |
| Custom SSH port | `./launch-pi.sh --port 2222 image.img` | `./launch-direct.sh --port 2222 image.img` |
| Dry run | `./launch-pi.sh --dry-run image.img` | `./launch-direct.sh --dry-run image.img` |
| Help | `./launch-pi.sh --help` | `./launch-direct.sh --help` |

### New features in emu2/:

| Feature | Command |
|---------|---------|
| VNC support | `./launch-direct.sh --vnc 5900 image.img` |
| Memory control | `./launch-direct.sh --memory 1G image.img` |
| CPU cores | `./launch-direct.sh --cores 2 image.img` |
| Verbose output | `./launch-direct.sh --verbose image.img` |

## Troubleshooting Migration

### "Image doesn't boot"
- **Cause**: Using non-NixOS images with emu2/
- **Solution**: Use NixOS images built by this repository, or stick with emu/ for generic images

### "Missing kernel files"
- **Cause**: Expecting file extraction behavior from emu/
- **Solution**: emu2/ doesn't extract files - it boots directly. This is expected.

### "Boot takes longer"
- **Cause**: emu2/ goes through the full boot process like real hardware
- **Solution**: This is normal. The system boots via U-Boot just like real hardware.

### "Different boot messages"
- **Cause**: Real boot process vs. direct kernel boot
- **Solution**: emu2/ shows authentic boot messages from U-Boot and Linux kernel

## When to use each framework

### Use emu2/ when:
- ✅ Working with NixOS images from this repository
- ✅ Want authentic hardware simulation
- ✅ Need reliable macOS support
- ✅ Prefer simple, robust tooling

### Use emu/ when:
- ⚠️ Working with generic Raspberry Pi OS images
- ⚠️ Need the old workflow for legacy reasons
- ⚠️ Have specific requirements for file extraction

## Recommendation

**For new projects and NixOS images, use emu2/.** It's simpler, more reliable, and designed specifically for the images built by this repository.

The original emu/ directory remains available for compatibility, but emu2/ is the recommended approach going forward.