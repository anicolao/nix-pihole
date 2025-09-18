# Reproducible Raspberry Pi 4 Emulation with Nix and QEMU

This document describes how to use the `emu/` directory to create a virtual machine that simulates a Raspberry Pi 3 or 4. The environment is managed by a Nix flake to ensure all dependencies are available, and the `launch-pi.sh` script automates the setup and execution.

The script requires you to choose between Pi 3 and Pi 4 emulation.

- **Pi 3 (`--pi3`)**: Recommended. This emulation is mature and stable in QEMU.
- **Pi 4 (`--pi4`)**: Experimental. This emulation is newer and may be unstable, but reflects the more modern hardware.

---

## 1. Environment Setup (Flake)

The `emu/flake.nix` file defines a shell environment containing the exact version of QEMU and other tools required, ensuring the setup is identical across any machine. You can enter this environment by running `nix develop` inside the `emu/` directory.

---

## 2. The Launch Script (`launch-pi.sh`)

This script automates the process of preparing and launching the virtual machine. It extracts the necessary boot files from a NixOS-built SD card image and starts QEMU with the correct configuration for the chosen Raspberry Pi model.

The script is located in the `emu/` directory. Here is a summary of its functionality:

- **Requires `--pi3` or `--pi4`**: You must specify which hardware to emulate.
- **Extracts Boot Files**: It mounts the provided SD card image and copies the necessary device tree (`.dtb`) and U-Boot kernel files.
- **Launches QEMU**: It assembles and executes a `qemu-system-aarch64` command with the correct parameters for the selected Pi model.
- **Forwards SSH**: It maps a local port (default: 5022) to the VM's SSH port (22), allowing you to connect.
- **Cleans Up**: It automatically removes temporary files on exit.

Below is the updated `launch-pi.sh` script for reference.

```bash
#!/bin/bash
set -e # Exit immediately if a command fails

# --- Default Configuration ---
MACHINE_TYPE=""
CPU_TYPE="cortex-a72"
DTB_FILE=""
KERNEL_FILE="u-boot-rpi4.bin"
SSH_FORWARD_PORT="5022"
MODEL=""

# --- Helper functions ---
show_help() {
	cat <<EOF
Usage: $0 < --pi3 | --pi4 > [OPTIONS] /path/to/raspberry-pi.img

Launch a Raspberry Pi emulator using QEMU.

REQUIRED:
    --pi3           Use Raspberry Pi 3 emulation (recommended, stable)
    --pi4           Use Raspberry Pi 4 emulation (experimental, may be unstable)

OPTIONS:
    --help          Show this help message
    --port PORT     Use custom SSH forward port (default: 5022)
    --dry-run       Show the QEMU command that would be executed without running it

EXAMPLES:
    $0 --pi3 nixos-pi-image.img
    $0 --pi4 --port 2222 nixos-pi-image.img

The script will:
1. Extract device tree files from the specified image
2. Launch QEMU with the selected Raspberry Pi emulation
3. Forward SSH from localhost:PORT to the VM's port 22
4. Clean up temporary files upon exit

To connect via SSH once the VM is running:
    ssh <user>@localhost -p $SSH_FORWARD_PORT

To exit the VM, press Ctrl-A then X.
EOF
}

# ... (The rest of the script contains OS-specific mounting functions and the main logic) ...
```

---

## 3. How to Run the Emulation

Follow these steps to build, resize, and emulate a Pi image.

#### Step 1: Build the SD Card Image
First, build the desired image using Nix. This example uses the Pi 4 target.
```shell
# Build the Pi 4 image
nix build .#images.rpi4
```

#### Step 2: Resize the Image
For emulation, it's best to expand the image to a larger size (e.g., 8GB).

```bash
# Create a directory for the resized image
mkdir -p images

# Identify the source image
SOURCE_IMAGE=$(ls result/sd-image/nixos-sd-image-*.img | head -n 1)

# Resize it
qemu-img resize -f raw "$SOURCE_IMAGE" 8G

# Move it to the images/ directory
mv "$SOURCE_IMAGE" images/nixos-pi4-8g.img
```

#### Step 3: Launch the VM
Navigate to the `emu` directory, enter the Nix shell, and run the launch script, specifying `--pi3` or `--pi4`.

```shell
# Enter the emulation environment
cd emu/
nix develop

# Launch the VM (choose one)
./launch-pi.sh --pi4 ../images/nixos-pi4-8g.img
# OR
./launch-pi.sh --pi3 ../images/nixos-pi4-8g.img
```

**Note:** The script will print a warning for `--pi4` because it is less stable.

#### Step 4: Connect via SSH
Once the VM has booted, connect to it from another terminal.
```shell
ssh root@localhost -p 5022
```
You will need to use the user and SSH key you configured in your NixOS build.

---

## 4. Troubleshooting

- **VM fails to boot**:
  - If using `--pi4`, try again with `--pi3`, as it is more stable.
  - Ensure the `.img` file is a valid NixOS-built ARM64 image.
  - Check that the device tree file (`.dtb`) inside the image matches the hardware (`bcm2711...` for Pi 4, `bcm2710...` for Pi 3).

- **"Permission denied" on SSH**:
  - Verify you are using the correct SSH private key for the user configured in the NixOS image.
  - Ensure the SSH port (`5022` by default) is not already in use on your host machine.

- **`qemu-img` or `qemu-system-aarch64` not found**:
  - Make sure you are inside the Nix shell by running `nix develop` in the `emu/` directory.
