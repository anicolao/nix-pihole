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
    --machine TYPE  QEMU machine type (raspi4b|virt) (default: raspi4b)
                    raspi4b: Raspberry Pi 4 hardware emulation (most accurate)
                    virt: Generic ARM virtualization platform (better console support)
    --console MODE  Serial console mode for nographic (mux|telnet|none|debug) (default: mux)
                    mux: multiplexed console (Ctrl-A c to switch monitor/serial)
                    telnet: serial via telnet on port 4444  
                    none: disable monitor, serial only to stdio
                    debug: log all serial devices to files for troubleshooting
                    NOTE: Console mapping depends on machine type and image configuration

EXAMPLES:
    $0 nixos-sd-image-rpi4.img
    $0 --machine virt --console none nixos-sd-image-rpi4.img
    $0 --console debug nixos-sd-image-rpi4.img
    $0 --port 2222 nixos-sd-image-rpi4.img
    $0 --vnc 5901 --memory 1G nixos-sd-image-rpi4.img
    $0 --dry-run nixos-sd-image-rpi4.img

MACHINE TYPE NOTES:
    raspi4b: Accurate Pi4 hardware emulation, but serial console can be tricky
    virt: Generic ARM platform with better QEMU serial support, good for debugging

CONSOLE TROUBLESHOOTING:
    If you see no console output with raspi4b machine:
    1. Try: --machine virt --console none
    2. Try: --console debug (logs all serial devices to files)
    3. Check if your image has serial console enabled in kernel/systemd

This script boots the image just like real hardware would:
1. QEMU emulates the specified hardware platform  
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
CONSOLE_MODE="mux"

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
        --machine)
            MACHINE_TYPE="$2"
            if [[ "$MACHINE_TYPE" != "raspi4b" && "$MACHINE_TYPE" != "virt" ]]; then
                echo "❌ Invalid machine type: $MACHINE_TYPE"
                echo "   Valid types: raspi4b, virt"
                exit 1
            fi
            # Adjust CPU type for virt machine
            if [[ "$MACHINE_TYPE" == "virt" ]]; then
                CPU_TYPE="cortex-a57"  # Better supported on virt machine
            fi
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
        --console)
            CONSOLE_MODE="$2"
            if [[ "$CONSOLE_MODE" != "mux" && "$CONSOLE_MODE" != "telnet" && "$CONSOLE_MODE" != "none" && "$CONSOLE_MODE" != "debug" ]]; then
                echo "❌ Invalid console mode: $CONSOLE_MODE"
                echo "   Valid modes: mux, telnet, none, debug"
                exit 1
            fi
            shift 2
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

# Check if QEMU is available (skip for dry run)
if [[ "$DRY_RUN" != "true" ]] && ! command -v qemu-system-aarch64 &> /dev/null; then
    echo "❌ qemu-system-aarch64 not found"
    echo "   Please run: nix develop"
    exit 1
fi

# Validate image
check_image "$DISK_IMAGE"

echo "🚀 Preparing to launch emulation..."
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
)

# Configure storage based on machine type
if [[ "$MACHINE_TYPE" == "virt" ]]; then
    # For virt machine, use virtio block device
    QEMU_CMD+=(-drive "if=virtio,format=raw,file=$DISK_IMAGE")
else
    # For raspi4b, use SD card interface
    QEMU_CMD+=(-drive "if=sd,format=raw,file=$DISK_IMAGE")
fi

# Network setup with SSH forwarding
QEMU_CMD+=(
    -netdev "user,id=net0,hostfwd=tcp::$SSH_FORWARD_PORT-:22"
)

# Configure network device based on machine type
if [[ "$MACHINE_TYPE" == "virt" ]]; then
    # Use virtio-net for virt machine (more reliable)
    QEMU_CMD+=(-device "virtio-net,netdev=net0")
else
    # Use USB network for raspi4b (Pi4 compatible)
    QEMU_CMD+=(-device "usb-net,netdev=net0")
fi

# Add VNC or nographic mode
if [[ "$ENABLE_VNC" == "true" ]]; then
    QEMU_CMD+=(-vnc ":$(($VNC_PORT - 5900))")
    # When using VNC, we need explicit serial console for debugging
    QEMU_CMD+=(-serial stdio)
else
    # Configure serial console based on machine type and mode
    if [[ "$MACHINE_TYPE" == "virt" ]]; then
        # virt machine has simpler, more reliable serial console support
        case "$CONSOLE_MODE" in
            "mux")
                # Multiplexed console: both QEMU monitor and serial console
                QEMU_CMD+=(-nographic -serial mon:stdio)
                ;;
            "telnet")
                # Serial console via telnet
                QEMU_CMD+=(-nographic -serial telnet:localhost:4444,server,nowait)
                ;;
            "none")
                # Disable monitor, use stdio for serial console only
                QEMU_CMD+=(-nographic -monitor none -serial stdio)
                ;;
            "debug")
                # Log multiple serial devices for debugging
                QEMU_CMD+=(-nographic -monitor none)
                for i in {1..5}; do
                    QEMU_CMD+=(-serial "file:serial-${i}.log")
                done
                ;;
        esac
    else
        # raspi4b machine type - handle Raspberry Pi specific serial mapping
        case "$CONSOLE_MODE" in
            "mux")
                # For Pi4: disable PL011 (ttyAMA0), use mini UART (ttyS0) with mux
                QEMU_CMD+=(-nographic -serial null -serial mon:stdio)
                ;;
            "telnet")
                # For Pi4: disable PL011, map mini UART to telnet
                QEMU_CMD+=(-nographic -serial null -serial telnet:localhost:4444,server,nowait)
                ;;
            "none")
                # For Pi4: disable PL011, map mini UART to stdio
                QEMU_CMD+=(-nographic -monitor none -serial null -serial stdio)
                ;;
            "debug")
                # For Pi4: log all possible serial devices for analysis
                QEMU_CMD+=(-nographic -monitor none)
                for i in {1..5}; do
                    QEMU_CMD+=(-serial "file:raspi-serial-${i}.log")
                done
                ;;
        esac
    fi
fi

# Add verbose options if requested
if [[ "$VERBOSE" == "true" ]]; then
    QEMU_CMD+=(-d guest_errors)
fi

# Show command or execute
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 Dry run - would execute:"
    echo "${QEMU_CMD[*]}"
else
    echo "🎯 Launching QEMU with direct boot..."
    echo "   The system will boot from the image's bootloader"
    echo "   Watch for boot messages and login prompt"
    if [[ "$ENABLE_VNC" == "true" ]]; then
        echo "   Press Ctrl-A then X to exit"
    else
        case "$CONSOLE_MODE" in
            "mux")
                if [[ "$MACHINE_TYPE" == "virt" ]]; then
                    echo "   Press Ctrl-A c to switch between QEMU monitor and serial console"
                else
                    echo "   Press Ctrl-A c to switch between QEMU monitor and serial console (ttyS0)"
                fi
                echo "   Press Ctrl-A x to exit"
                ;;
            "telnet")
                if [[ "$MACHINE_TYPE" == "virt" ]]; then
                    echo "   Connect to serial console with: telnet localhost 4444"
                else
                    echo "   Connect to serial console (ttyS0) with: telnet localhost 4444"
                fi
                echo "   Press Ctrl-A x to exit QEMU"
                ;;
            "none")
                if [[ "$MACHINE_TYPE" == "virt" ]]; then
                    echo "   Serial console output should appear directly"
                else
                    echo "   Serial console (ttyS0) output should appear directly"
                fi
                echo "   Press Ctrl-A x to exit"
                ;;
            "debug")
                if [[ "$MACHINE_TYPE" == "virt" ]]; then
                    echo "   Serial devices are logged to: serial-1.log through serial-5.log"
                else
                    echo "   Serial devices are logged to: raspi-serial-1.log through raspi-serial-5.log"
                fi
                echo "   Monitor with: tail -f *.log"
                echo "   Press Ctrl-A x to exit"
                ;;
        esac
    fi
    echo ""
    
    # Execute QEMU
    exec "${QEMU_CMD[@]}"
fi