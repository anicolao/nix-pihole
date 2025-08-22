# Direct-Boot Raspberry Pi 4 Emulation (emu2)

This directory contains a **simplified, robust emulation framework** designed specifically for NixOS Raspberry Pi images built by this repository. Unlike the original `emu/` approach, this framework boots images directly without file extraction, just like real hardware.

## Key Advantages over emu/

✅ **No file extraction required** - Works directly with SD card images  
✅ **Boots via U-Boot** - Mimics real hardware boot process  
✅ **Works with NixOS images** - Designed for images built by this repo's `flake.nix`  
✅ **macOS friendly** - No complex mounting operations  
✅ **Simpler and more reliable** - Fewer moving parts, fewer failure points  
✅ **Cross-platform** - Consistent behavior on Linux and macOS  

## Quick Start

1. **Enter the development environment:**
   ```bash
   cd emu2/
   nix develop
   ```

2. **Build a NixOS image** (from repository root):
   ```bash
   nix build .#images.rpi4
   ```

3. **Launch the emulator:**
   ```bash
   ./launch-direct.sh result/sd-image/nixos-sd-image-*.img
   ```

4. **Connect via SSH** once the system boots:
   ```bash
   ssh [username]@localhost -p 5022
   ```

## How It Works

### Direct Boot Process
Unlike the original `emu/` that extracts kernel and device tree files:

1. **QEMU emulates** the complete Raspberry Pi 4 hardware
2. **Image boots naturally** via its built-in U-Boot bootloader  
3. **No file extraction** or complex mounting operations
4. **Boot process mirrors** real hardware exactly

### Architecture
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   NixOS Image   │───▶│  QEMU Hardware   │───▶│   Booted Linux  │
│  (with U-Boot)  │    │   Emulation      │    │    System       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Usage Examples

### Basic Usage
```bash
./launch-direct.sh nixos-sd-image-rpi4.img
```

### Custom SSH Port
```bash
./launch-direct.sh --port 2222 nixos-sd-image-rpi4.img
```

### Enable VNC for Graphical Access
```bash
./launch-direct.sh --vnc 5901 nixos-sd-image-rpi4.img
```

### Lower Memory for Slower Systems
```bash
./launch-direct.sh --memory 1G --cores 2 nixos-sd-image-rpi4.img
```

### Debug Boot Issues
```bash
./launch-direct.sh --verbose nixos-sd-image-rpi4.img
```

### Test Command Without Execution
```bash
./launch-direct.sh --dry-run nixos-sd-image-rpi4.img
```

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `--port PORT` | SSH forward port | 5022 |
| `--vnc PORT` | VNC server port (enables graphics) | disabled |
| `--memory SIZE` | RAM size (1G, 2G, 4G) | 2G |
| `--cores N` | CPU cores | 4 |
| `--verbose` | Enable debug output | disabled |
| `--dry-run` | Show command without running | disabled |

## Requirements

- **Nix with flakes support**
- **QEMU with ARM64 support** (provided by flake)
- **NixOS SD image** built for Raspberry Pi 4

## Troubleshooting

### Boot Issues
- Use `--verbose` to see detailed boot messages
- Try `--memory 1G` if running on limited hardware
- Ensure the image is a valid NixOS SD card image

### Console Output Issues
- **Console output should appear immediately** after the "Launching QEMU" message
- If you see **no boot messages** but QEMU appears to be running, this indicates a serial console configuration issue
- The framework automatically configures ARM UART console (`-chardev stdio,id=char0 -serial chardev:char0`) with kernel parameters (`console=ttyAMA0,115200`) to ensure console output is visible
- In VNC mode, console output appears in the terminal while graphics appear in the VNC viewer

### Network Issues  
- **Slirp network errors**: Fixed by using `virtio-net-pci` instead of `usb-net` for better compatibility with Raspberry Pi 4 emulation
- **SSH connection issues**: Wait for complete boot process (may take 1-2 minutes)
- Check SSH service is enabled in the NixOS configuration
- Verify the SSH forward port isn't already in use

### Performance Issues
- Reduce `--cores` and `--memory` for slower host systems
- Disable VNC if running headless: `--vnc` is optional

### macOS Specific
- No special requirements - should work out of the box
- No complex mounting operations required

## Comparison with Original emu/

| Feature | emu/ (old) | emu2/ (new) |
|---------|------------|-------------|
| File extraction | Required | Not needed |
| macOS compatibility | Complex mounting | Simple |
| Boot method | Manual kernel/DTB | Natural U-Boot |
| Image support | Generic RaspOS | NixOS optimized |
| Reliability | Mounting can fail | Direct boot |
| Complexity | High | Low |

## Development

The framework consists of:

- **`flake.nix`** - Nix development environment with QEMU
- **`launch-direct.sh`** - Main launch script
- **`README.md`** - This documentation

To extend or modify:

1. Modify `launch-direct.sh` for different QEMU options
2. Update `flake.nix` to add development tools
3. Test with various NixOS image configurations

## Integration with Repository

This emulation framework is designed to work seamlessly with:

- Images built by the main `flake.nix` in this repository
- The modular NixOS configuration system
- Pi-hole and networking configurations
- Custom user configurations

Simply build an image and boot it - no additional setup required.