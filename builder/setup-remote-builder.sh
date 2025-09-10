#!/bin/bash
# Setup script for Colima-based remote builder for NixOS aarch64-linux builds

set -e

echo "🚀 Setting up Colima Remote Builder for aarch64-linux"
echo "===================================================="
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

# Remove existing container if it exists
echo "🧹 Cleaning up any existing container..."
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker rm -f nix-remote-builder 2>/dev/null || true

# Create a NixOS container with Nix daemon for remote building
echo "🚀 Starting NixOS container..."
DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker run -d \
    --name nix-remote-builder \
    --platform linux/arm64 \
    --privileged \
    -p 2222:22 \
    -v nix-store:/nix \
    -v nix-var:/var \
    nixos/nix:latest \
    /bin/sh -c "
        set -e
        echo 'Starting container initialization...'
        
        # Install openssh and enable sshd
        echo 'Installing SSH server...'
        nix-env -iA nixpkgs.openssh nixpkgs.shadow || exit 1
        
        # Create necessary directories
        mkdir -p /var/empty /run/sshd /root/.ssh /etc/nix
        
        # Generate host keys
        echo 'Generating SSH host keys...'
        ssh-keygen -A || exit 1
        
        # Enable nix features
        echo 'Configuring Nix...'
        echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf
        echo 'trusted-users = root' >> /etc/nix/nix.conf
        
        # Start the nix daemon in background
        echo 'Starting Nix daemon...'
        nix-daemon &
        
        # Start SSH daemon in foreground
        echo 'Starting SSH daemon...'
        exec \$(which sshd) -D -e
    "

# Check if container started successfully
sleep 5
if ! DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker ps | grep -q nix-remote-builder; then
    echo "❌ Container failed to start. Checking logs..."
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder
    exit 1
fi

echo "🔑 Setting up SSH access to remote builder..."

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/nix-builder" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/nix-builder" -N "" -C "nix-remote-builder"
    echo "🔑 Generated SSH key: $HOME/.ssh/nix-builder"
fi

# Wait for container to be ready
echo "⏳ Waiting for NixOS container to be ready..."
echo "   This may take up to 60 seconds..."

# Wait for SSH service to be available
for i in {1..12}; do
    if DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker exec nix-remote-builder pgrep sshd > /dev/null 2>&1; then
        echo "✅ SSH daemon is running in container"
        break
    fi
    if [ $i -eq 12 ]; then
        echo "❌ SSH daemon failed to start in container"
        echo "Container logs:"
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder
        exit 1
    fi
    echo "   Waiting for SSH daemon... (attempt $i/12)"
    sleep 5
done

# Copy SSH public key to container
echo "🔑 Setting up SSH key authentication..."
if ! DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker exec nix-remote-builder \
    /bin/sh -c "echo '$(cat $HOME/.ssh/nix-builder.pub)' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"; then
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

# Test SSH connection with retries
for i in {1..6}; do
    if timeout 10 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p 2222 root@localhost "nix --version" > /dev/null 2>&1; then
        echo "✅ Remote builder SSH connection successful"
        break
    fi
    if [ $i -eq 6 ]; then
        echo "❌ Remote builder SSH connection failed after multiple attempts"
        echo "ℹ️  Container status:"
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker ps -a | grep nix-remote-builder
        echo "ℹ️  Container logs:"
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker logs nix-remote-builder | tail -20
        echo "ℹ️  Port check:"
        nc -z localhost 2222 && echo "Port 2222 is open" || echo "Port 2222 is not accessible"
        exit 1
    fi
    echo "   Testing SSH connection... (attempt $i/6)"
    sleep 5
done

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