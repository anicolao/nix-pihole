#!/bin/bash
# Integration demo script showing how to build and emulate a NixOS image

set -e

echo "🚀 NixOS Pi-hole Image Build and Emulation Demo"
echo "==============================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "../flake.nix" ]]; then
    echo "❌ Please run this script from the emu2/ directory"
    echo "   The main repository flake.nix should be in the parent directory"
    exit 1
fi

echo "📁 Working from emu2/ directory"
echo "📁 Main repository detected at ../"
echo ""

# Step 1: Validate the framework
echo "🧪 Step 1: Validating the emulation framework..."
if ! ./validate-framework.sh >/dev/null 2>&1; then
    echo "❌ Framework validation failed"
    exit 1
fi
echo "✅ Framework validation passed"
echo ""

# Step 2: Enter Nix development environment (if not already)
echo "🔧 Step 2: Checking development environment..."
if ! command -v qemu-system-aarch64 &> /dev/null; then
    echo "⚠️  QEMU not found. Please run:"
    echo "   nix develop"
    echo "   Then run this script again from within the nix develop shell"
    exit 1
fi
echo "✅ QEMU development environment ready"
echo ""

# Step 3: Check if image already exists
echo "🔍 Step 3: Checking for existing NixOS image..."
cd ..  # Go to main repository

# Look for existing result symlink
if [[ -L "result" ]] && [[ -d "result/sd-image" ]]; then
    IMAGE_FILE=$(find result/sd-image -name "*.img" | head -1)
    if [[ -n "$IMAGE_FILE" ]]; then
        echo "✅ Found existing image: $IMAGE_FILE"
        SKIP_BUILD=true
    else
        echo "⚠️  Result directory exists but no .img file found"
        SKIP_BUILD=false
    fi
else
    echo "📦 No existing image found, will need to build"
    SKIP_BUILD=false
fi
echo ""

# Step 4: Build image if needed
if [[ "$SKIP_BUILD" != "true" ]]; then
    echo "🏗️  Step 4: Building NixOS Raspberry Pi image..."
    echo "   This may take several minutes on first build..."
    
    if command -v nix &> /dev/null; then
        echo "   Running: nix build .#images.rpi4"
        nix build .#images.rpi4 --show-trace
        
        # Find the built image
        IMAGE_FILE=$(find result/sd-image -name "*.img" | head -1)
        if [[ -n "$IMAGE_FILE" ]]; then
            echo "✅ Image built successfully: $IMAGE_FILE"
        else
            echo "❌ Image build completed but no .img file found"
            exit 1
        fi
    else
        echo "❌ Nix not available for building. Please install Nix first."
        exit 1
    fi
else
    echo "⏭️  Step 4: Skipping build (using existing image)"
fi
echo ""

# Step 5: Image information
echo "📊 Step 5: Image information"
echo "   File: $IMAGE_FILE"

# Get image size
if [[ -f "$IMAGE_FILE" ]]; then
    SIZE=$(stat -c%s "$IMAGE_FILE" 2>/dev/null || stat -f%z "$IMAGE_FILE" 2>/dev/null || echo "unknown")
    if [[ "$SIZE" != "unknown" ]]; then
        SIZE_MB=$((SIZE / 1024 / 1024))
        echo "   Size: ${SIZE_MB}MB"
    fi
    
    # Check file type
    echo "   Type: $(file "$IMAGE_FILE" | cut -d: -f2-)"
fi
echo ""

# Step 6: Prepare emulation
echo "🎯 Step 6: Preparing emulation"
cd emu2  # Go back to emu2 directory

echo "   Image path: ../$IMAGE_FILE"
echo "   SSH will be available on localhost:5022"
echo "   Press Ctrl-A then X to exit QEMU"
echo ""

# Step 7: Offer launch options
echo "🚀 Step 7: Launch options"
echo ""
echo "Choose how to launch the emulation:"
echo "  1) Launch immediately"
echo "  2) Show QEMU command (dry-run)"
echo "  3) Launch with VNC (graphical)"
echo "  4) Launch with custom settings"
echo "  5) Cancel"
echo ""

read -p "Enter choice (1-5): " choice

case $choice in
    1)
        echo "🚀 Launching emulation..."
        exec ./launch-direct.sh "../$IMAGE_FILE"
        ;;
    2)
        echo "🔍 QEMU command that would be executed:"
        ./launch-direct.sh --dry-run "../$IMAGE_FILE"
        ;;
    3)
        echo "🖥️  Launching with VNC (connect to localhost:5900)..."
        exec ./launch-direct.sh --vnc 5900 "../$IMAGE_FILE"
        ;;
    4)
        echo ""
        echo "Custom settings:"
        read -p "SSH port (default 5022): " ssh_port
        read -p "Memory size (default 2G): " memory
        read -p "CPU cores (default 4): " cores
        
        EXTRA_ARGS=()
        [[ -n "$ssh_port" ]] && EXTRA_ARGS+=(--port "$ssh_port")
        [[ -n "$memory" ]] && EXTRA_ARGS+=(--memory "$memory") 
        [[ -n "$cores" ]] && EXTRA_ARGS+=(--cores "$cores")
        
        echo "🚀 Launching with custom settings..."
        exec ./launch-direct.sh "${EXTRA_ARGS[@]}" "../$IMAGE_FILE"
        ;;
    5)
        echo "👋 Cancelled"
        exit 0
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac