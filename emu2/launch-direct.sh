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
    --machine TYPE  QEMU machine type (raspi4b|virt|test) (default: raspi4b)
                    raspi4b: Raspberry Pi 4 hardware emulation (most accurate)
                    virt: Generic ARM virtualization platform (better console support)
                    test: Minimal test configuration for console debugging
    --console MODE  Serial console mode for nographic (mux|telnet|none|debug|inspect|firmware) (default: mux)
                    mux: multiplexed console (Ctrl-A c to switch monitor/serial)
                    telnet: serial via telnet on port 4444  
                    none: disable monitor, serial only to stdio
                    debug: log all serial devices to files for troubleshooting
                    inspect: comprehensive analysis mode - logs everything + shows system state
                    firmware: focus on boot firmware diagnostics with minimal logging
                    NOTE: Console mapping depends on machine type and image configuration

EXAMPLES:
    $0 nixos-sd-image-rpi4.img
    $0 --machine virt --console none nixos-sd-image-rpi4.img
    $0 --console debug nixos-sd-image-rpi4.img
    $0 --machine test --console inspect nixos-sd-image-rpi4.img
    $0 --console firmware nixos-sd-image-rpi4.img
    $0 --port 2222 nixos-sd-image-rpi4.img
    $0 --vnc 5901 --memory 1G nixos-sd-image-rpi4.img
    $0 --dry-run nixos-sd-image-rpi4.img

MACHINE TYPE NOTES:
    raspi4b: Accurate Pi4 hardware emulation, but serial console can be tricky
    virt: Generic ARM platform with better QEMU serial support, good for debugging
    test: Uses virt machine with minimal config for console troubleshooting

CONSOLE TROUBLESHOOTING:
    If you see no console output with any machine or console mode:
    1. Try: --machine test --console inspect (minimal test config with analysis)
    2. Try: --console firmware (focused boot diagnostics)
    3. Check if your NixOS image has these kernel parameters: console=ttyAMA0,115200 console=ttyS0,115200
    4. Verify the image boots by checking CPU/memory usage in another terminal
    5. The image may not have serial console enabled - check systemd getty configuration
    6. Run ./troubleshoot-console.sh (created in inspect mode) to analyze log files
    7. If only CPU resets occur in debug logs: bootloader/firmware issue, not console config

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
            if [[ "$MACHINE_TYPE" != "raspi4b" && "$MACHINE_TYPE" != "virt" && "$MACHINE_TYPE" != "test" ]]; then
                echo "❌ Invalid machine type: $MACHINE_TYPE"
                echo "   Valid types: raspi4b, virt, test"
                exit 1
            fi
            # Adjust CPU type for different machines
            if [[ "$MACHINE_TYPE" == "virt" ]]; then
                CPU_TYPE="cortex-a57"  # Better supported on virt machine
            elif [[ "$MACHINE_TYPE" == "test" ]]; then
                CPU_TYPE="cortex-a57"  # Use reliable CPU for testing
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
            if [[ "$CONSOLE_MODE" != "mux" && "$CONSOLE_MODE" != "telnet" && "$CONSOLE_MODE" != "none" && "$CONSOLE_MODE" != "debug" && "$CONSOLE_MODE" != "inspect" && "$CONSOLE_MODE" != "firmware" ]]; then
                echo "❌ Invalid console mode: $CONSOLE_MODE"
                echo "   Valid modes: mux, telnet, none, debug, inspect, firmware"
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
elif [[ "$MACHINE_TYPE" == "test" ]]; then
    # For test machine, use virt with minimal config
    MACHINE_TYPE="virt"  # Override to use virt for testing
    QEMU_CMD[1]="-machine"  # Update the machine parameter
    QEMU_CMD[2]="virt"      # Set to virt
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
if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
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
    if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
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
            "inspect")
                # Comprehensive analysis mode - logs everything and provides system monitoring
                QEMU_CMD+=(-nographic -monitor stdio)
                # Log all serial devices
                for i in {1..5}; do
                    QEMU_CMD+=(-serial "file:serial-${i}.log")
                done
                # Add debugging options to see what's happening
                QEMU_CMD+=(-d guest_errors,unimp,cpu_reset,exec,in_asm,op_opt -D qemu-debug.log)
                ;;
            "firmware")
                # Focus on boot firmware diagnostics
                QEMU_CMD+=(-nographic -monitor stdio)
                # Minimal serial logging for boot analysis
                QEMU_CMD+=(-serial "file:boot-console.log")
                # Focused debugging on boot process and firmware
                QEMU_CMD+=(-d guest_errors,unimp,cpu_reset,exec -D boot-firmware.log)
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
            "inspect")
                # Comprehensive analysis mode for Pi4
                QEMU_CMD+=(-nographic -monitor stdio)
                # Log all serial devices with different routing attempts
                QEMU_CMD+=(-serial "file:raspi-serial-1.log")  # PL011 UART (ttyAMA0)
                QEMU_CMD+=(-serial "file:raspi-serial-2.log")  # Mini UART (ttyS0)
                QEMU_CMD+=(-serial "file:raspi-serial-3.log")  # Additional UARTs
                QEMU_CMD+=(-serial "file:raspi-serial-4.log")
                QEMU_CMD+=(-serial "file:raspi-serial-5.log")
                # Enable comprehensive debugging including boot diagnostics
                QEMU_CMD+=(-d guest_errors,unimp,cpu_reset,int,exec,in_asm,op_opt -D qemu-raspi-debug.log)
                ;;
            "firmware")
                # Focus on boot firmware diagnostics for Pi4
                QEMU_CMD+=(-nographic -monitor stdio)
                # Single serial log for boot analysis
                QEMU_CMD+=(-serial "file:raspi-boot-console.log")
                # Focused debugging on boot process
                QEMU_CMD+=(-d guest_errors,unimp,cpu_reset,exec -D raspi-boot-firmware.log)
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
                if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
                    echo "   Press Ctrl-A c to switch between QEMU monitor and serial console"
                else
                    echo "   Press Ctrl-A c to switch between QEMU monitor and serial console (ttyS0)"
                fi
                echo "   Press Ctrl-A x to exit"
                ;;
            "telnet")
                if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
                    echo "   Connect to serial console with: telnet localhost 4444"
                else
                    echo "   Connect to serial console (ttyS0) with: telnet localhost 4444"
                fi
                echo "   Press Ctrl-A x to exit QEMU"
                ;;
            "none")
                if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
                    echo "   Serial console output should appear directly"
                else
                    echo "   Serial console (ttyS0) output should appear directly"
                fi
                echo "   Press Ctrl-A x to exit"
                ;;
            "debug")
                if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
                    echo "   Serial devices are logged to: serial-1.log through serial-5.log"
                else
                    echo "   Serial devices are logged to: raspi-serial-1.log through raspi-serial-5.log"
                fi
                echo "   Monitor with: tail -f *.log"
                echo "   Press Ctrl-A x to exit"
                ;;
            "inspect")
                if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
                    echo "   Comprehensive analysis mode active:"
                    echo "   - Serial devices logged to: serial-1.log through serial-5.log"
                    echo "   - QEMU debug log: qemu-debug.log"
                    echo "   - QEMU monitor available for system inspection"
                    echo "   Monitor serial with: tail -f serial-*.log"
                else
                    echo "   Comprehensive analysis mode active:"
                    echo "   - raspi-serial-1.log: PL011 UART (ttyAMA0)"
                    echo "   - raspi-serial-2.log: Mini UART (ttyS0)"  
                    echo "   - raspi-serial-3,4,5.log: Additional UARTs"
                    echo "   - QEMU debug log: qemu-raspi-debug.log"
                    echo "   - QEMU monitor available for system inspection"
                    echo "   Monitor serial with: tail -f raspi-serial-*.log"
                fi
                echo "   Use QEMU monitor commands: info registers, info qtree, info chardev"
                echo "   Press Ctrl-A x to exit"
                ;;
            "firmware")
                if [[ "$MACHINE_TYPE" == "virt" || "$MACHINE_TYPE" == "test" ]]; then
                    echo "   Boot firmware analysis mode:"
                    echo "   - Console log: boot-console.log"
                    echo "   - Firmware debug: boot-firmware.log"
                else
                    echo "   Pi4 boot firmware analysis mode:"
                    echo "   - Console log: raspi-boot-console.log"
                    echo "   - Firmware debug: raspi-boot-firmware.log"
                fi
                echo "   Monitor with: tail -f *boot*.log"
                echo "   Use QEMU monitor: info registers, info status"
                echo "   Press Ctrl-A x to exit"
                ;;
        esac
    fi
    echo ""
    
    # Create troubleshooting helper script for inspect mode
    if [[ "$CONSOLE_MODE" == "inspect" ]]; then
        cat > troubleshoot-console.sh << 'EOF'
#!/bin/bash
echo "=== Serial Console Troubleshooting Helper ==="
echo "This script monitors all log files and provides analysis."
echo ""

# Function to check if any logs have content
check_logs() {
    local found_output=false
    echo "📋 Checking log files for output..."
    
    for log in *serial*.log *boot*.log qemu*.log; do
        if [[ -f "$log" ]]; then
            local size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo "0")
            if [[ "$size" -gt 0 ]]; then
                echo "✅ $log: $size bytes"
                found_output=true
            else
                echo "📝 $log: empty"
            fi
        fi
    done
    
    if [[ "$found_output" == "false" ]]; then
        echo ""
        echo "❌ No serial output found in any log file."
        echo "This suggests one of these issues:"
        echo "   1. NixOS image lacks serial console configuration"
        echo "   2. Bootloader (U-Boot) not configured for serial output"
        echo "   3. Kernel parameters missing console= directives"
        echo "   4. systemd getty not enabled for serial console"
        echo ""
        echo "🔍 CRITICAL: Check qemu-debug.log or qemu-raspi-debug.log for boot analysis:"
        echo "   - If only CPU resets shown: Boot process not starting"
        echo "   - Look for 'Trying to execute code' messages to see if bootloader runs"
        echo "   - Check for SD card/storage access attempts"
        echo "   - Monitor for any actual instruction execution beyond resets"
        echo ""
        echo "🔧 Advanced troubleshooting steps:"
        echo "   1. Check if the image is actually booting (monitor CPU usage)"
        echo "   2. Try mounting the image to check /boot/config.txt and kernel parameters"
        echo "   3. Use a different NixOS image known to have serial console working"
        echo "   4. Check if SSH is accessible (may indicate system is running without serial)"
        echo "   5. If only CPU resets occur, the bootloader may not be found/executed"
        echo "   6. Try different machine types (virt vs raspi4b) to isolate hardware emulation issues"
        return 1
    else
        echo ""
        echo "✅ Found output! Check the non-empty log files above."
        return 0
    fi
}

# Function to monitor logs in real-time
monitor_logs() {
    echo ""
    echo "📺 Starting real-time log monitoring..."
    echo "   Press Ctrl-C to stop monitoring"
    echo ""
    
    # Find all log files and tail them
    local log_files=()
    for log in *serial*.log *boot*.log qemu*.log; do
        [[ -f "$log" ]] && log_files+=("$log")
    done
    
    if [[ ${#log_files[@]} -gt 0 ]]; then
        tail -f "${log_files[@]}"
    else
        echo "❌ No log files found to monitor"
    fi
}

# Function to analyze debug logs for boot issues
analyze_boot() {
    echo ""
    echo "🔍 Analyzing boot process from debug logs..."
    echo ""
    
    local debug_log=""
    if [[ -f "raspi-boot-firmware.log" ]]; then
        debug_log="raspi-boot-firmware.log"
    elif [[ -f "boot-firmware.log" ]]; then
        debug_log="boot-firmware.log"
    elif [[ -f "qemu-raspi-debug.log" ]]; then
        debug_log="qemu-raspi-debug.log"
    elif [[ -f "qemu-debug.log" ]]; then
        debug_log="qemu-debug.log"
    fi
    
    if [[ -n "$debug_log" && -f "$debug_log" ]]; then
        echo "📋 Analyzing: $debug_log"
        
        # Count CPU resets
        local resets=$(grep -c "CPU Reset" "$debug_log" 2>/dev/null || echo "0")
        echo "   CPU Resets: $resets"
        
        # Look for execution beyond resets
        local exec_lines=$(grep -c "Trying to execute\|Taking exception\|IN:" "$debug_log" 2>/dev/null || echo "0")
        echo "   Code execution attempts: $exec_lines"
        
        # Check for storage access
        local storage_access=$(grep -c "sd\|mmc\|block" "$debug_log" 2>/dev/null || echo "0")
        echo "   Storage access attempts: $storage_access"
        
        # Look for bootloader activity
        local bootloader=$(grep -c -i "boot\|u-boot\|loader" "$debug_log" 2>/dev/null || echo "0")
        echo "   Bootloader references: $bootloader"
        
        echo ""
        if [[ "$exec_lines" -eq 0 && "$resets" -gt 0 ]]; then
            echo "❌ DIAGNOSIS: System resets but never executes code"
            echo "   This indicates the bootloader is not being found or executed."
            echo "   Possible causes:"
            echo "   - SD card image boot partition not recognized by QEMU"
            echo "   - Missing or incompatible bootloader (U-Boot) in image"
            echo "   - QEMU raspi4b boot firmware issues"
            echo "   - Image partition table or filesystem corruption"
        elif [[ "$exec_lines" -gt 0 ]]; then
            echo "✅ DIAGNOSIS: Code execution detected"
            echo "   The bootloader appears to be running. Check serial logs for output."
        else
            echo "⚠️  DIAGNOSIS: No clear boot process detected"
            echo "   The debug log may need more verbose logging options."
        fi
        
        echo ""
        echo "📄 Recent debug log entries:"
        tail -20 "$debug_log"
    else
        echo "❌ No debug log found (qemu-debug.log or qemu-raspi-debug.log)"
    fi
}

# Main menu
echo "Choose an option:"
echo "1) Check current log files for output"
echo "2) Monitor log files in real-time"
echo "3) Analyze boot process from debug logs"
echo "4) Show all analysis"
echo ""
read -p "Enter choice (1-4): " choice

case "$choice" in
    1)
        check_logs
        ;;
    2)
        monitor_logs
        ;;
    3)
        analyze_boot
        ;;
    4)
        check_logs
        echo ""
        analyze_boot
        echo ""
        monitor_logs
        ;;
    *)
        echo "Invalid choice"
        ;;
esac
EOF
        chmod +x troubleshoot-console.sh
        echo "📋 Created troubleshoot-console.sh script for analysis"
    fi
    
    # Execute QEMU
    exec "${QEMU_CMD[@]}"
fi