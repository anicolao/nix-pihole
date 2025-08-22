# Reproducible Raspberry Pi 4 Emulation with Nix and QEMU

This document provides a programmatic and reproducible method for creating a virtual machine that simulates a Raspberry Pi 4. The entire environment is managed by a Nix flake to ensure consistency, and a launch script automates the setup and execution process.

This guide prioritizes the use of the Raspberry Pi 4 board emulation. However, as Pi 4 emulation in QEMU can sometimes be less stable than its predecessor, a fallback option to the more mature Pi 3 board emulation is also documented.

---

## 1. Nix Flake for Environment Setup

This file, `flake.nix`, defines a shell environment containing the exact version of QEMU required, ensuring the setup is identical across any machine.

```nix
# flake.nix
{
  description = "A reproducible QEMU environment for Raspberry Pi emulation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Change to "x86_64-darwin" for Intel Macs
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          # The core emulator for ARM64 systems
          pkgs.qemu_full
        ];
      };
    };
}
```

---

## 2. The Launch Script

This script automates the entire process of preparing and launching the virtual machine. It extracts the necessary boot files from the SD card image and starts QEMU with the correct configuration for a Raspberry Pi 4.

Create this file and name it `launch-pi.sh`.

```bash
#!/bin/bash
set -e # Exit immediately if a command fails

# --- Configuration for Raspberry Pi 4 ---
MACHINE_TYPE="raspi4b"
CPU_TYPE="cortex-a72"
DTB_FILE="bcm2711-rpi-4-b.dtb" # Device Tree Blob for Pi 4 Model B
KERNEL_FILE="kernel8.img"      # 64-bit kernel image name
SSH_FORWARD_PORT="5022"        # Host port to forward to the VM's SSH port 22

# --- Script Logic ---
if [[ -z "$1" ]]; then
  echo "Usage: $0 /path/to/raspberry-pi.img"
  exit 1
fi

DISK_IMAGE="$1"
WORKDIR=$(pwd)

echo "✅ Attaching disk image to extract boot files..."
# Attach the raw disk image and find the mount point of the boot partition
BOOT_MOUNT=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage "$DISK_IMAGE" | grep 'FDisk_partition_scheme' | cut -f3)

if [[ -z "$BOOT_MOUNT" ]]; then
    echo "❌ Failed to mount the boot partition. Is the image valid?"
    exit 1
fi

echo "✅ Copying kernel and DTB from the image..."
cp "$BOOT_MOUNT/$DTB_FILE" "$WORKDIR/"
cp "$BOOT_MOUNT/$KERNEL_FILE" "$WORKDIR/"

echo "✅ Detaching disk image..."
hdiutil detach "$BOOT_MOUNT"

echo "🚀 Launching QEMU (Pi 4 Emulation)..."
echo "   Connect via SSH: ssh pi@localhost -p $SSH_FORWARD_PORT"
echo "   To exit, press Ctrl-A then X."

# Launch the VM using the extracted files and the original image as the SD card
qemu-system-aarch64 \
  -M "$MACHINE_TYPE" \
  -cpu "$CPU_TYPE" \
  -m 2G \
  -smp 4 \
  -dtb "$WORKDIR/$DTB_FILE" \
  -kernel "$WORKDIR/$KERNEL_FILE" \
  -drive "if=sd,format=raw,file=$DISK_IMAGE" \
  -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootdelay=1" \
  -netdev "user,id=net0,hostfwd=tcp::$SSH_FORWARD_PORT-:22" \
  -device "usb-net,netdev=net0" \
  -nographic

echo "🧹 Cleaning up temporary boot files..."
rm "$WORKDIR/$DTB_FILE" "$WORKDIR/$KERNEL_FILE"

echo "✅ VM shut down."
```

---

## 3. How to Run the Virtual Pi

#### Step 1: Make the script executable
```shell
chmod +x launch-pi.sh
```

#### Step 2: Enter the Nix Shell
This command makes the `qemu-system-aarch64` program available in your terminal.
```shell
nix develop
```

#### Step 3: Launch the VM
From inside the Nix shell, run the script and pass the path to your Raspberry Pi `.img` file as an argument.
```shell
./launch-pi.sh /path/to/your/raspios-image.img
```

#### Step 4: Connect via SSH
Once the VM finishes its boot sequence, open a new terminal window on your Mac and connect to it using SSH. The default password for Raspberry Pi OS is `raspberry`.
```shell
ssh pi@localhost -p 5022
```

---

## 4. Troubleshooting and Fallback to Pi 3

**Why have a fallback?** The Raspberry Pi 4 board emulation (`raspi4b`) is newer and can sometimes be less stable in QEMU than the mature `raspi3b` emulation. If you experience unexpected crashes, boot failures, or instability, falling back to the Pi 3 board is a reliable troubleshooting step.

**How to switch to the Pi 3 fallback:**

Simply edit the "Configuration" section at the top of the `launch-pi.sh` script to use the Pi 3 values:

```bash
# --- Configuration for Raspberry Pi 3 (Fallback) ---
MACHINE_TYPE="raspi3b"
CPU_TYPE="cortex-a72" # Keep the faster CPU for performance
DTB_FILE="bcm2710-rpi-3-b-plus.dtb" # Pi 3B+ Device Tree
KERNEL_FILE="kernel8.img"
SSH_FORWARD_PORT="5022"
```

Save the file and re-run the script. This will use the stable Pi 3 board emulation while still benefiting from the faster Pi 4 CPU, offering a good balance of stability and performance.
