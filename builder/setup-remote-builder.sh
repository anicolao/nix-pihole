#!/bin/bash
# Setup script for Colima-based remote builder for NixOS aarch64-linux builds

set -e

echo "🚀 Setting up Colima Remote Builder for aarch64-linux"
echo "===================================================="
echo

# Configuration
COLIMA_PROFILE="nix-builder"
COLIMA_ARCH="aarch64"
COLIMA_MEMORY="4GB"
COLIMA_DISK="20GB"
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
        exit 0
    fi
fi

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

# Test Docker connection
echo "🧪 Testing Docker connection..."
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker info > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Docker connection successful"
else
    echo "❌ Docker connection failed"
    exit 1
fi

echo "🐳 Setting up NixOS Docker container for remote building..."

# Create a NixOS container with Nix daemon for remote building
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker run -d \
    --name nix-remote-builder \
    --platform linux/arm64 \
    --privileged \
    -p 2222:22 \
    -v nix-store:/nix \
    -v nix-var:/var \
    nixos/nix:latest \
    /bin/sh -c "
        # Install openssh and enable sshd
        nix-env -iA nixpkgs.openssh nixpkgs.shadow
        mkdir -p /var/empty /run/sshd /root/.ssh
        
        # Generate host keys
        ssh-keygen -A
        
        # Enable nix features
        mkdir -p /etc/nix
        echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf
        echo 'trusted-users = root' >> /etc/nix/nix.conf
        
        # Start the nix daemon and sshd
        nix-daemon &
        /usr/sbin/sshd -D
    " || echo "Container might already exist"

echo "🔑 Setting up SSH access to remote builder..."

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/nix-builder" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/nix-builder" -N "" -C "nix-remote-builder"
    echo "🔑 Generated SSH key: $HOME/.ssh/nix-builder"
fi

# Wait for container to be ready
echo "⏳ Waiting for NixOS container to be ready..."
sleep 10

# Copy SSH public key to container
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker exec nix-remote-builder \
    /bin/sh -c "echo '$(cat $HOME/.ssh/nix-builder.pub)' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"

echo "🔧 Configuring Nix remote builder..."

# Create nix remote builder configuration
mkdir -p "$HOME/.config/nix"
cat > "$HOME/.config/nix/nix.conf" << EOF
experimental-features = nix-command flakes
builders = ssh://root@localhost:2222 aarch64-linux $HOME/.ssh/nix-builder 4 1 nixos-test,benchmark,big-parallel,kvm - -
builders-use-substitutes = true
EOF

echo "🧪 Testing remote builder connection..."
if timeout 30 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -p 2222 root@localhost "nix --version" > /dev/null 2>&1; then
    echo "✅ Remote builder SSH connection successful"
else
    echo "❌ Remote builder SSH connection failed"
    echo "ℹ️  Container logs:"
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder | tail -20
    exit 1
fi

echo
echo "✅ Remote builder setup complete!"
echo
echo "📋 Configuration summary:"
echo "  - Colima profile: $COLIMA_PROFILE ($COLIMA_ARCH)"
echo "  - NixOS container: nix-remote-builder"
echo "  - SSH port: 2222"
echo "  - SSH key: $HOME/.ssh/nix-builder"
echo
echo "🎯 Usage:"
echo "  export DOCKER_HOST=\"unix://\$HOME/.colima/$COLIMA_PROFILE/docker.sock\""
echo "  nix build .#images.rpi4 --builders \"ssh://root@localhost:2222\""
echo
echo "🔧 To start the builder later:"
echo "  colima start $COLIMA_PROFILE"
echo "  DOCKER_HOST=\"unix://\$HOME/.colima/$COLIMA_PROFILE/docker.sock\" docker start nix-remote-builder"
echo