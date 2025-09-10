#!/bin/bash
# Build script for Pi-hole RPi4 image using Colima remote builder

set -e

echo "🚀 Building Pi-hole RPi4 Image with Remote Builder"
echo "=================================================="
echo

# Configuration
COLIMA_PROFILE="nix-builder"
BUILD_TARGET="images.rpi4"

# Check if we're in the right directory
if [ ! -f "flake.nix" ]; then
    echo "❌ Please run this script from the repository root (where flake.nix is located)"
    exit 1
fi

# Check if colima is available
if ! command -v colima &> /dev/null; then
    echo "❌ Colima not found. Please run: nix develop"
    exit 1
fi

# Check if nix is available
if ! command -v nix &> /dev/null; then
    echo "❌ Nix not found. Please run: nix develop"
    exit 1
fi

echo "🔍 Checking remote builder setup..."
if ! colima list | grep -q "$COLIMA_PROFILE"; then
    echo "❌ Remote builder not set up"
    echo "ℹ️  Run: ./builder/setup-remote-builder.sh"
    exit 1
fi

if ! colima status "$COLIMA_PROFILE" | grep -q "Running"; then
    echo "🚀 Starting Colima profile '$COLIMA_PROFILE'..."
    colima start "$COLIMA_PROFILE"
fi

# Set Docker host for Colima
export DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock"

# Check if NixOS container is running
if ! docker ps | grep -q "nix-remote-builder"; then
    echo "🚀 Starting NixOS remote builder container..."
    docker start nix-remote-builder || {
        echo "❌ Failed to start remote builder container"
        echo "ℹ️  Run: ./builder/setup-remote-builder.sh"
        exit 1
    }
    sleep 5
fi

echo "✅ Remote builder is ready"
echo "  Profile: $COLIMA_PROFILE"
echo "  Container: nix-remote-builder"
echo "  SSH port: 2222"
echo

# Check for personal configuration
if [ ! -d "personal" ] || [ ! -f "personal/alex_users.nix" ]; then
    echo "⚠️  Personal configuration not found"
    echo "ℹ️  Using default configuration. To customize:"
    echo "   mkdir -p personal"
    echo "   cp templates/users.nix.example personal/alex_users.nix"
    echo "   cp templates/secrets.nix.example personal/secrets.nix"
    echo "   # Edit the files with your settings"
    echo
fi

echo "🏗️  Starting build process..."
echo "  Target: $BUILD_TARGET"
echo "  Using remote builder: ssh://root@localhost:2222"
echo

# Prepare build command
BUILD_CMD="nix build .#$BUILD_TARGET --builders 'ssh://root@localhost:2222 aarch64-linux $HOME/.ssh/nix-builder 4 1 nixos-test,benchmark,big-parallel,kvm'"

# Show build command
echo "📋 Build command:"
echo "  $BUILD_CMD"
echo

# Estimate build time
echo "⏱️  Build time estimate: 10-30 minutes (depending on system and network)"
echo "📊 This will build a complete NixOS system for aarch64-linux architecture"
echo

# Ask for confirmation
read -p "🚀 Start the build? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "👋 Build cancelled"
    exit 0
fi

echo "🔨 Building $BUILD_TARGET..."
echo "   (This may take a while - grab a coffee! ☕)"
echo

# Run the build with timing
START_TIME=$(date +%s)

if eval "$BUILD_CMD"; then
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    BUILD_MINUTES=$((BUILD_TIME / 60))
    BUILD_SECONDS=$((BUILD_TIME % 60))
    
    echo
    echo "✅ Build completed successfully!"
    echo "⏱️  Build time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    echo
    
    # Show result information
    if [ -L "result" ]; then
        RESULT_PATH=$(readlink -f result)
        echo "📦 Build result:"
        echo "  Symlink: result -> $RESULT_PATH"
        
        # Find the image file
        if [ -d "$RESULT_PATH" ]; then
            IMAGE_FILE=$(find "$RESULT_PATH" -name "*.img" | head -1)
            if [ -n "$IMAGE_FILE" ]; then
                IMAGE_SIZE=$(du -h "$IMAGE_FILE" | cut -f1)
                echo "  Image: $IMAGE_FILE"
                echo "  Size: $IMAGE_SIZE"
                echo
                echo "🎯 Next steps:"
                echo "  1. Flash to SD card: sudo dd if=\"$IMAGE_FILE\" of=/dev/sdX bs=4M status=progress"
                echo "  2. Or test in emulator: cd emu2 && ./demo-integration.sh"
            else
                echo "  Directory: $RESULT_PATH"
                echo "  (Image file not found in expected location)"
            fi
        fi
    else
        echo "📦 Build completed but result symlink not found"
    fi
    
else
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    BUILD_MINUTES=$((BUILD_TIME / 60))
    BUILD_SECONDS=$((BUILD_TIME % 60))
    
    echo
    echo "❌ Build failed after ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    echo
    echo "🔍 Troubleshooting:"
    echo "  1. Check remote builder: ./builder/test-remote-builder.sh"
    echo "  2. Check container logs: docker logs nix-remote-builder"
    echo "  3. Verify SSH connection: ssh -i ~/.ssh/nix-builder -p 2222 root@localhost"
    echo "  4. Try rebuilding remote builder: ./builder/setup-remote-builder.sh"
    exit 1
fi

echo
echo "🎉 Pi-hole RPi4 image build complete!"
echo
echo "📋 Summary:"
echo "  - Built on remote aarch64-linux builder"
echo "  - Image ready for Raspberry Pi 4"
echo "  - Includes Pi-hole DNS filtering"
echo "  - SSH access configured"
echo
echo "📚 Documentation:"
echo "  - Main README: README.md"
echo "  - Emulation guide: PI4_EMULATOR.md"
echo "  - Test proposal: TEST_PROPOSAL.md"
echo