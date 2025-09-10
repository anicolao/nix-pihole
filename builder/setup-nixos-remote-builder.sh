#!/bin/bash
# Setup script for Colima-based remote builder using NixOS container
# This replaces the manual SSH setup with a proper NixOS configuration

set -e

echo "🚀 Setting up Colima Remote Builder with NixOS Container"
echo "======================================================="
echo

# Configuration
COLIMA_PROFILE="nix-builder"
COLIMA_ARCH="aarch64"
COLIMA_MEMORY="4"
COLIMA_DISK="20"
COLIMA_CPU="4"

# Check if colima is available
if ! command -v colima &> /dev/null; then
    echo "❌ Colima not found. Please install colima first:"
    echo "   brew install colima"
    echo "   Or run: nix develop"
    exit 1
fi

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install docker first:"
    echo "   brew install docker"
    echo "   Or run: nix develop"
    exit 1
fi

echo "🔍 Checking existing Colima profile..."
if colima list | grep -q "$COLIMA_PROFILE"; then
    echo "⚠️  Colima profile '$COLIMA_PROFILE' already exists"
    read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Stopping and deleting existing profile..."
        colima stop "$COLIMA_PROFILE" || true
        colima delete "$COLIMA_PROFILE" || true
    else
        echo "ℹ️  Using existing profile"
        if ! colima status "$COLIMA_PROFILE" | grep -q "Running"; then
            echo "🚀 Starting existing Colima profile..."
            colima start "$COLIMA_PROFILE"
        fi
        echo "✅ Colima profile '$COLIMA_PROFILE' is ready"
    fi
fi

# Start Colima if not already running
if ! colima status "$COLIMA_PROFILE" | grep -q "Running" 2>/dev/null; then
    echo "🏗️  Creating new Colima profile with aarch64 architecture..."
    colima start \
        --profile "$COLIMA_PROFILE" \
        --arch "$COLIMA_ARCH" \
        --memory "$COLIMA_MEMORY" \
        --disk "$COLIMA_DISK" \
        --cpu "$COLIMA_CPU" \
        --vm-type=vz \
        --vz-rosetta

    echo "⏳ Waiting for Colima to be ready..."
    sleep 5
fi

# Test Docker connection
echo "🧪 Testing Docker connection..."
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker info > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Docker connection successful"
else
    echo "❌ Docker connection failed"
    exit 1
fi

echo "🏗️  Building NixOS remote builder container image..."

# Build the NixOS container image
echo "📦 Building NixOS container with proper SSH configuration..."
if ! nix build .#images.remote-builder --system aarch64-linux; then
    echo "❌ Failed to build NixOS container image"
    echo "ℹ️  Make sure you have a remote builder configured or are on an aarch64 system"
    echo "ℹ️  You can also use the improved container approach: ./setup-remote-builder.sh"
    exit 1
fi

# Load the built image into Docker
echo "📤 Loading NixOS container image into Docker..."
if [ -f result ]; then
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker load < result
else
    echo "❌ Build result not found"
    exit 1
fi

# Get the image ID/name from the loaded image
IMAGE_NAME=$(DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker images --format "{{.Repository}}:{{.Tag}}" | grep "nix-remote-builder" | head -n1)
if [ -z "$IMAGE_NAME" ]; then
    echo "❌ Failed to find the built image"
    echo "Available images:"
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker images
    exit 1
fi

echo "🐳 Setting up NixOS container for remote building..."

# Remove existing container if it exists
echo "🧹 Cleaning up any existing container..."
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker rm -f nix-remote-builder 2>/dev/null || true

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/nix-builder" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/nix-builder" -N "" -C "nix-remote-builder"
    echo "🔑 Generated SSH key: $HOME/.ssh/nix-builder"
fi

echo "🚀 Starting NixOS container with declarative SSH configuration..."
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker run -d \
    --name nix-remote-builder \
    --platform linux/arm64 \
    --privileged \
    -p 2222:22 \
    -v nix-store:/nix \
    "$IMAGE_NAME"

# Wait a moment for the container to start and initialize
echo "⏳ Waiting for NixOS container to initialize..."
sleep 15

# Check if container started successfully
if ! DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker ps | grep -q nix-remote-builder; then
    echo "❌ Container failed to start. Checking logs..."
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder
    exit 1
fi

echo "🔑 Setting up SSH key authentication..."

# Copy SSH public key to container
if ! DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker exec nix-remote-builder \
    /bin/sh -c "mkdir -p /root/.ssh && echo '$(cat $HOME/.ssh/nix-builder.pub)' > /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"; then
    echo "❌ Failed to setup SSH key authentication"
    echo "Container logs:"
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder | tail -20
    exit 1
fi

echo "🔧 Configuring Nix remote builder..."

# Create nix remote builder configuration
mkdir -p "$HOME/.config/nix"
cat > "$HOME/.config/nix/nix.conf" << EOF
experimental-features = nix-command flakes
builders = ssh://root@localhost:2222 aarch64-linux $HOME/.ssh/nix-builder 4 1 nixos-test,benchmark,big-parallel,kvm - -
builders-use-substitutes = true
EOF

echo "🧪 Testing remote builder connection..."

# Wait for SSH service to be ready
for i in {1..12}; do
    if timeout 10 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p 2222 root@localhost "echo 'SSH connection successful'" > /dev/null 2>&1; then
        echo "✅ Remote builder SSH connection successful"
        break
    fi
    if [ $i -eq 12 ]; then
        echo "❌ Remote builder SSH connection failed after multiple attempts"
        echo "ℹ️  Container status:"
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker ps -a | grep nix-remote-builder
        echo "ℹ️  Container logs:"
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder | tail -20
        echo "ℹ️  Port check:"
        nc -z localhost 2222 && echo "Port 2222 is open" || echo "Port 2222 is not accessible"
        exit 1
    fi
    echo "   Testing SSH connection... (attempt $i/12)"
    sleep 5
done

# Test Nix functionality
echo "🔍 Testing Nix functionality on remote builder..."
if timeout 30 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -p 2222 root@localhost "nix --version" > /dev/null 2>&1; then
    echo "✅ Nix is working on remote builder"
else
    echo "⚠️  Nix test failed, but SSH connection works. Container may still be initializing."
fi

echo
echo "✅ NixOS remote builder setup complete!"
echo
echo "📋 Configuration summary:"
echo "  - Colima profile: $COLIMA_PROFILE ($COLIMA_ARCH)"
echo "  - NixOS container: nix-remote-builder (proper NixOS with systemd)"
echo "  - SSH port: 2222"
echo "  - SSH key: $HOME/.ssh/nix-builder"
echo "  - Container image: $IMAGE_NAME"
echo
echo "🎯 Usage:"
echo "  export DOCKER_HOST=\"unix://\$HOME/.colima/$COLIMA_PROFILE/docker.sock\""
echo "  nix build .#images.rpi4 --builders \"ssh://root@localhost:2222\""
echo
echo "🔧 To start the builder later:"
echo "  colima start $COLIMA_PROFILE"
echo "  DOCKER_HOST=\"unix://\$HOME/.colima/$COLIMA_PROFILE/docker.sock\" docker start nix-remote-builder"
echo