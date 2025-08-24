#!/bin/bash
set -e # Exit immediately if a command fails

# --- Configuration for Raspberry Pi 4 ---
MACHINE_TYPE="raspi4b"
CPU_TYPE="cortex-a72"
DTB_FILE="bcm2711-rpi-4-b.dtb" # Device Tree Blob for Pi 4 Model B
KERNEL_FILE="u-boot-rpi4.bin"  # U-Boot binary for Raspberry Pi 4
SSH_FORWARD_PORT="5022"        # Host port to forward to the VM's SSH port 22

# --- Helper functions ---
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] /path/to/raspberry-pi.img

Launch a Raspberry Pi 4 emulator using QEMU.

OPTIONS:
    --help          Show this help message
    --pi3           Use Pi 3 fallback configuration for better stability
    --port PORT     Use custom SSH forward port (default: 5022)
    --dry-run       Show the QEMU command that would be executed without running it

EXAMPLES:
    $0 raspios-lite.img
    $0 --pi3 raspios-lite.img
    $0 --port 2222 raspios-lite.img
    $0 --dry-run raspios-lite.img

The script will:
1. Extract device tree files and use u-boot for booting
2. Launch QEMU with Raspberry Pi 4 emulation
3. Forward SSH from localhost:PORT to the VM
4. Clean up temporary files when done

To connect via SSH once the VM is running:
    ssh pi@localhost -p $SSH_FORWARD_PORT

To exit the VM, press Ctrl-A then X.
EOF
}

mount_image_linux() {
    local image="$1"
    local mount_point
    
    echo "✅ Setting up loop device for disk image..." >&2
    
    # Create loop device for the image
    LOOP_DEVICE=$(sudo losetup --find --show --partscan "$image")
    
    # Find the boot partition (usually partition 1)
    if [[ -e "${LOOP_DEVICE}p1" ]]; then
        BOOT_PARTITION="${LOOP_DEVICE}p1"
    else
        echo "❌ Could not find boot partition on $LOOP_DEVICE" >&2
        sudo losetup -d "$LOOP_DEVICE"
        exit 1
    fi
    
    # Create temporary mount point
    mount_point=$(mktemp -d)
    
    echo "✅ Mounting boot partition..." >&2
    sudo mount "$BOOT_PARTITION" "$mount_point"
    
    echo "$mount_point"
}

unmount_image_linux() {
    local mount_point="$1"
    
    echo "✅ Unmounting boot partition..." >&2
    sudo umount "$mount_point"
    
    echo "✅ Detaching loop device..." >&2
    sudo losetup -d "$LOOP_DEVICE"
    
    # Clean up mount point
    rmdir "$mount_point"
}

mount_image_macos() {
    local image="$1"
    
    echo "✅ Attaching disk image to extract boot files..." >&2
    # Attach the raw disk image and find the mount point of the boot partition
    BOOT_MOUNT=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage "$image" | grep 'Volume' | cut -f3)
    
    if [[ -z "$BOOT_MOUNT" ]]; then
        echo "❌ Failed to mount the boot partition. Is the image valid?" >&2
        exit 1
    fi
    
    echo "$BOOT_MOUNT"
}

unmount_image_macos() {
    local mount_point="$1"
    
    echo "✅ Detaching disk image..." >&2
    hdiutil detach "$mount_point"
}

# --- Parse command line arguments ---
DRY_RUN=false
USE_PI3=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --pi3)
            USE_PI3=true
            shift
            ;;
        --port)
            SSH_FORWARD_PORT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
        *)
            DISK_IMAGE="$1"
            shift
            ;;
    esac
done

# --- Validate arguments ---
if [[ -z "$DISK_IMAGE" ]]; then
    echo "Error: No disk image specified" >&2
    echo "Usage: $0 [OPTIONS] /path/to/raspberry-pi.img" >&2
    echo "Use --help for more information." >&2
    exit 1
fi

if [[ ! -f "$DISK_IMAGE" ]]; then
    echo "❌ Disk image not found: $DISK_IMAGE" >&2
    exit 1
fi

# --- Apply Pi 3 fallback configuration if requested ---
if [[ "$USE_PI3" == "true" ]]; then
    echo "🔄 Using Raspberry Pi 3 fallback configuration..." >&2
    MACHINE_TYPE="raspi3b"
    DTB_FILE="bcm2710-rpi-3-b-plus.dtb"
fi

# --- Script Logic ---
WORKDIR=$(pwd)

# For dry-run mode, we can skip the actual mounting and just simulate
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 Dry-run mode: Validating image and showing command..." >&2
    echo "✅ Image file exists: $DISK_IMAGE" >&2
    echo "✅ Would extract device tree files and use u-boot kernel" >&2
    echo "✅ Would copy $DTB_FILE and $KERNEL_FILE to $WORKDIR" >&2
    
    # Create fake temporary files for dry-run
    touch "$WORKDIR/$DTB_FILE" "$WORKDIR/$KERNEL_FILE"
    
    # Set up cleanup for dry-run
    cleanup() {
        echo "🧹 Cleaning up temporary files from dry-run..." >&2
        rm -f "$WORKDIR/$DTB_FILE" "$WORKDIR/$KERNEL_FILE"
    }
    trap cleanup EXIT
else
    # Detect OS and use appropriate mounting method
    if [[ "$OSTYPE" == "darwin"* ]]; then
        BOOT_MOUNT=$(mount_image_macos "$DISK_IMAGE")
        CLEANUP_FUNC="unmount_image_macos"
    else
        BOOT_MOUNT=$(mount_image_linux "$DISK_IMAGE")
        CLEANUP_FUNC="unmount_image_linux"
    fi

    # Set up cleanup trap
    cleanup() {
        if [[ -n "$BOOT_MOUNT" ]]; then
            $CLEANUP_FUNC "$BOOT_MOUNT"
        fi
        
        # Clean up temporary boot files
        if [[ -f "$WORKDIR/$DTB_FILE" ]]; then
            echo "🧹 Cleaning up temporary boot files..." >&2
            rm -f "$WORKDIR/$DTB_FILE" "$WORKDIR/$KERNEL_FILE"
        fi
    }
    trap cleanup EXIT

    echo "✅ Copying device tree from image and using u-boot kernel..." >&2
    if [[ ! -f "$BOOT_MOUNT/$DTB_FILE" ]]; then
        echo "❌ Device tree file not found: $BOOT_MOUNT/$DTB_FILE" >&2
        echo "   This might not be a valid Raspberry Pi image." >&2
        exit 1
    fi

    if [[ ! -f "$BOOT_MOUNT/$KERNEL_FILE" ]]; then
        echo "❌ U-Boot file not found: $BOOT_MOUNT/$KERNEL_FILE" >&2
        echo "   Looking for u-boot-rpi4.bin in the boot partition." >&2
        echo "   This might not be a valid Raspberry Pi image with u-boot." >&2
        exit 1
    fi

    cp "$BOOT_MOUNT/$DTB_FILE" "$WORKDIR/"
    cp "$BOOT_MOUNT/$KERNEL_FILE" "$WORKDIR/"

    # Cleanup mount early
    $CLEANUP_FUNC "$BOOT_MOUNT"
    BOOT_MOUNT=""
fi



echo "🚀 Launching QEMU ($(if [[ "$USE_PI3" == "true" ]]; then echo "Pi 3"; else echo "Pi 4"; fi) Emulation)..." >&2
echo "   Connect via SSH: ssh pi@localhost -p $SSH_FORWARD_PORT" >&2
echo "   To exit, press Ctrl-A then X." >&2
echo "" >&2

# Build QEMU command
QEMU_CMD=(
    qemu-system-aarch64
    -M "$MACHINE_TYPE"
    -cpu "$CPU_TYPE"
    -m 2G
    -smp 4
    -dtb "$WORKDIR/$DTB_FILE"
    -kernel "$WORKDIR/$KERNEL_FILE"
    -drive "if=sd,format=raw,file=$DISK_IMAGE"
    -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootdelay=1"
    -netdev "user,id=net0,hostfwd=tcp::$SSH_FORWARD_PORT-:22"
    -device "usb-net,netdev=net0"
    -nographic
)

if [[ "$DRY_RUN" == "true" ]]; then
    echo "Dry run - would execute:" >&2
    printf '%q ' "${QEMU_CMD[@]}"
    echo "" >&2
else
    # Launch the VM using the extracted files and the original image as the SD card
    "${QEMU_CMD[@]}"
    echo "" >&2
    echo "✅ VM shut down." >&2
fi