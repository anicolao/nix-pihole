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
DISK_IMAGE=""

if [[ $# -eq 0 ]]; then
	show_help
	exit 1
fi

while [[ $# -gt 0 ]]; do
	case $1 in
	--help)
		show_help
		exit 0
		;;
	--pi3)
		if [[ -n "$MACHINE_TYPE" ]]; then
			echo "Error: --pi3 and --pi4 are mutually exclusive." >&2
			exit 1
		fi
		MACHINE_TYPE="raspi3b"
		DTB_FILE="bcm2710-rpi-3-b-plus.dtb"
		MODEL="Pi 3"
		shift
		;;
	--pi4)
		if [[ -n "$MACHINE_TYPE" ]]; then
			echo "Error: --pi3 and --pi4 are mutually exclusive." >&2
			exit 1
		fi
		echo "⚠️  Warning: Raspberry Pi 4 emulation is experimental and may be unstable." >&2
		MACHINE_TYPE="raspi4b"
		DTB_FILE="bcm2711-rpi-4-b.dtb"
		MODEL="Pi 4"
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
		show_help >&2
		exit 1
		;;
	*)
		if [[ -z "$DISK_IMAGE" ]]; then
			DISK_IMAGE="$1"
		else
			echo "Error: Unexpected argument '$1'" >&2
			show_help >&2
			exit 1
		fi
		shift
		;;
	esac
done

# --- Validate arguments ---
if [[ -z "$MACHINE_TYPE" ]]; then
	echo "Error: You must specify --pi3 or --pi4." >&2
	show_help >&2
	exit 1
fi

if [[ -z "$DISK_IMAGE" ]]; then
	echo "Error: No disk image specified." >&2
	show_help >&2
	exit 1
fi

if [[ ! -f "$DISK_IMAGE" ]]; then
	echo "❌ Disk image not found: $DISK_IMAGE" >&2
	exit 1
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

if [[ "$MACHINE_TYPE" == "raspi3b" ]]; then
	RAM_SIZE="1G"
else
	RAM_SIZE="2G" # Pi 4 gets more RAM
fi

echo "🚀 Launching QEMU ($MODEL)..." >&2
echo "   Connect via SSH: ssh pi@localhost -p $SSH_FORWARD_PORT" >&2
echo "   To exit, press Ctrl-A then X." >&2
echo "" >&2

# Build QEMU command
QEMU_CMD=(
	qemu-system-aarch64
	-M "$MACHINE_TYPE"
	-cpu "$CPU_TYPE"
	-m "${RAM_SIZE}"
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
