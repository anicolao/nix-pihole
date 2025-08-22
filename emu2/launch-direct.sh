#!/bin/bash
set -e # Exit immediately if a command fails

# --- Configuration for Direct Boot Raspberry Pi 4 Emulation ---
MACHINE_TYPE="raspi4b"
CPU_TYPE="cortex-a72" 
MEMORY="2G"
SMP_CORES="4"
SSH_FORWARD_PORT="5022"
VNC_PORT="5900"

# Global variables for cleanup
TEMP_FILES=()

# --- Helper functions ---
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] /path/to/nixos-rpi4-image.img

Launch a Raspberry Pi 4 emulator using direct boot from NixOS SD image.
This approach boots directly from the image without extracting files.

OPTIONS:
    --help          Show this help message
    --port PORT     Use custom SSH forward port (default: 5022)
    --vnc PORT      Enable VNC server on specified port (default: 5900)
    --memory SIZE   Set memory size (default: 2G, try 1G for slower systems)
    --cores N       Set number of CPU cores (default: 4)
    --dry-run       Show the QEMU command without executing it
    --verbose       Enable verbose QEMU output

EXAMPLES:
    $0 nixos-sd-image-rpi4.img
    $0 --port 2222 nixos-sd-image-rpi4.img
    $0 --vnc 5901 --memory 1G nixos-sd-image-rpi4.img
    $0 --dry-run nixos-sd-image-rpi4.img

This script boots the image just like real hardware would:
1. QEMU emulates the Raspberry Pi 4 hardware
2. The image's U-Boot bootloader handles the boot process
3. No file extraction or mounting required
4. SSH is forwarded to localhost:PORT
5. VNC can be enabled for graphical access

To connect via SSH once the system boots:
    ssh [username]@localhost -p $SSH_FORWARD_PORT

To exit the VM, press Ctrl-A then X.
EOF
}

cleanup() {
    if [[ ${#TEMP_FILES[@]} -gt 0 ]]; then
        echo "🧹 Cleaning up temporary files..."
        for file in "${TEMP_FILES[@]}"; do
            [[ -f "$file" ]] && rm -f "$file"
        done
    fi
}

trap cleanup EXIT

check_image() {
    local image="$1"
    
    echo "🔍 Checking image file..."
    
    if [[ ! -f "$image" ]]; then
        echo "❌ Image file not found: $image"
        exit 1
    fi
    
    # Check file type
    local file_type=$(file "$image")
    echo "   File type: $file_type"
    
    # Check file size (should be reasonable for SD image)
    local size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null || echo "unknown")
    if [[ "$size" != "unknown" ]]; then
        local size_mb=$((size / 1024 / 1024))
        echo "   Size: ${size_mb}MB"
        
        if [[ $size_mb -lt 100 ]]; then
            echo "⚠️  Warning: Image seems very small for a full NixOS system"
        fi
    fi
    
    echo "✅ Image file appears valid"
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
DISK_IMAGE=""
ENABLE_VNC=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --port)
            SSH_FORWARD_PORT="$2"
            shift 2
            ;;
        --vnc)
            VNC_PORT="$2"
            ENABLE_VNC=true
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --cores)
            SMP_CORES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -*)
            echo "❌ Unknown option: $1"
            echo "   Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$DISK_IMAGE" ]]; then
                DISK_IMAGE="$1"
            else
                echo "❌ Multiple image files specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$DISK_IMAGE" ]]; then
    echo "❌ No disk image specified"
    echo "   Use --help for usage information"
    exit 1
fi

# Check if QEMU is available
if ! command -v qemu-system-aarch64 &> /dev/null; then
    echo "❌ qemu-system-aarch64 not found"
    echo "   Please run: nix develop"
    exit 1
fi

# Validate image
check_image "$DISK_IMAGE"

echo "🚀 Preparing to launch Raspberry Pi 4 emulation..."
echo "   Machine: $MACHINE_TYPE"
echo "   CPU: $CPU_TYPE"
echo "   Memory: $MEMORY"
echo "   Cores: $SMP_CORES"
echo "   SSH Forward: localhost:$SSH_FORWARD_PORT"
if [[ "$ENABLE_VNC" == "true" ]]; then
    echo "   VNC: localhost:$VNC_PORT"
fi
echo ""

# Build QEMU command for direct boot
QEMU_CMD=(
    qemu-system-aarch64
    -machine "$MACHINE_TYPE"
    -cpu "$CPU_TYPE"
    -m "$MEMORY"
    -smp "$SMP_CORES"
    # Use the SD card image directly as the boot device
    -drive "if=sd,format=raw,file=$DISK_IMAGE"
    # Network setup with SSH forwarding - use virtio-net for better compatibility
    -netdev "user,id=net0,hostfwd=tcp::$SSH_FORWARD_PORT-:22"
    -device "virtio-net-pci,netdev=net0"
)

# Add VNC or nographic mode
if [[ "$ENABLE_VNC" == "true" ]]; then
    QEMU_CMD+=(-vnc ":$(($VNC_PORT - 5900))")
    # When using VNC, we need explicit serial console for debugging
    QEMU_CMD+=(-serial stdio)
else
    # nographic mode with ARM UART console
    QEMU_CMD+=(-nographic)
    QEMU_CMD+=(-chardev stdio,id=char0 -serial chardev:char0)
fi

# Add verbose options if requested
if [[ "$VERBOSE" == "true" ]]; then
    QEMU_CMD+=(-d guest_errors)
fi

# Add kernel command line for better console and boot support
# These parameters help ensure console output and proper boot behavior
QEMU_CMD+=(-append "console=ttyAMA0,115200 console=tty1 earlyprintk=ttyAMA0,115200")

# Show command or execute
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 Dry run - would execute:"
    echo "${QEMU_CMD[*]}"
else
    echo "🎯 Launching QEMU with direct boot..."
    echo "   The system will boot from the image's bootloader"
    echo "   Watch for boot messages and login prompt"
    echo "   Press Ctrl-A then X to exit"
    echo ""
    
    # Execute QEMU
    exec "${QEMU_CMD[@]}"
fi