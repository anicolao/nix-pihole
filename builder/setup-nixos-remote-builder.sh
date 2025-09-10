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

# Ensure Docker buildx is available for multi-platform builds
if ! DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker buildx version &> /dev/null 2>&1 && ! docker buildx version &> /dev/null 2>&1; then
    echo "ℹ️  Setting up Docker buildx for multi-platform support..."
    # This will be attempted later when we need it
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
# Try to build natively first, then fall back to using Docker emulation
if ! nix build .#images.remote-builder 2>/dev/null; then
    echo "ℹ️  Native build failed, building with Docker emulation support..."
    # Use Docker's buildx with emulation as a fallback
    if command -v docker &> /dev/null; then
        echo "🔧 Creating temporary Dockerfile for NixOS remote builder..."
        cat > /tmp/Dockerfile.nix-builder << 'EOF'
FROM nixos/nix:latest

# Install required packages
RUN nix-env -iA nixpkgs.openssh nixpkgs.shadow nixpkgs.git nixpkgs.curl

# Create necessary directories
RUN mkdir -p /root/.ssh /etc/ssh /run/sshd /var/log /var/empty /etc/nix

# Configure Nix
RUN echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf && \
    echo 'trusted-users = root' >> /etc/nix/nix.conf && \
    echo 'auto-optimise-store = true' >> /etc/nix/nix.conf && \
    echo 'substituters = https://cache.nixos.org/' >> /etc/nix/nix.conf && \
    echo 'trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=' >> /etc/nix/nix.conf

# Generate SSH host keys and create config
RUN ssh-keygen -t rsa -b 2048 -f /etc/ssh/ssh_host_rsa_key -N "" && \
    ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N "" && \
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# Create sshd configuration
RUN echo 'Port 22' > /etc/ssh/sshd_config && \
    echo 'AddressFamily any' >> /etc/ssh/sshd_config && \
    echo 'ListenAddress 0.0.0.0' >> /etc/ssh/sshd_config && \
    echo 'HostKey /etc/ssh/ssh_host_rsa_key' >> /etc/ssh/sshd_config && \
    echo 'HostKey /etc/ssh/ssh_host_ecdsa_key' >> /etc/ssh/sshd_config && \
    echo 'HostKey /etc/ssh/ssh_host_ed25519_key' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config && \
    echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'AuthorizedKeysFile .ssh/authorized_keys' >> /etc/ssh/sshd_config && \
    echo 'UsePAM no' >> /etc/ssh/sshd_config && \
    echo 'X11Forwarding no' >> /etc/ssh/sshd_config && \
    echo 'PrintMotd no' >> /etc/ssh/sshd_config

# Create startup script
RUN echo '#!/bin/sh' > /bin/init-container.sh && \
    echo 'set -e' >> /bin/init-container.sh && \
    echo 'echo "Starting Nix Remote Builder Container..."' >> /bin/init-container.sh && \
    echo 'echo "Starting Nix daemon..."' >> /bin/init-container.sh && \
    echo 'nix-daemon &' >> /bin/init-container.sh && \
    echo 'sleep 2' >> /bin/init-container.sh && \
    echo 'echo "Starting SSH daemon..."' >> /bin/init-container.sh && \
    echo 'exec $(which sshd) -D -e' >> /bin/init-container.sh && \
    chmod +x /bin/init-container.sh

EXPOSE 22
CMD ["/bin/init-container.sh"]
EOF
        
        echo "🏗️  Building Docker image with emulation..."
        # First, ensure buildx is set up
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker buildx create --use --name nix-builder 2>/dev/null || true
        
        # Build the image using buildx for arm64 platform
        if DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker buildx build \
            --platform linux/arm64 \
            -t nix-remote-builder:latest \
            --load \
            -f /tmp/Dockerfile.nix-builder \
            /tmp; then
            echo "✅ Docker image built successfully with emulation"
        else
            echo "⚠️  Buildx failed, trying regular Docker build..."
            DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker build \
                -t nix-remote-builder:latest \
                -f /tmp/Dockerfile.nix-builder \
                /tmp
        fi
        
        # Clean up temp file
        rm -f /tmp/Dockerfile.nix-builder
    else
        echo "❌ Failed to build NixOS container image"
        echo "ℹ️  Neither Nix cross-compilation nor Docker is available"
        echo "ℹ️  You can use the working container approach instead:"
        echo "     ./setup-remote-builder.sh"
        exit 1
    fi
else
    echo "✅ Nix build successful"
fi

# Load the built image into Docker (only if we used Nix build)
if [ -f result ]; then
    echo "📤 Loading NixOS container image into Docker..."
    DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker load < result
    
    # Get the image ID/name from the loaded image
    IMAGE_NAME=$(DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker images --format "{{.Repository}}:{{.Tag}}" | grep "nix-remote-builder" | head -n1)
    if [ -z "$IMAGE_NAME" ]; then
        echo "❌ Failed to find the built image"
        echo "Available images:"
        DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock" docker images
        exit 1
    fi
else
    # Image was built with Docker, use the tag we specified
    IMAGE_NAME="nix-remote-builder:latest"
    echo "ℹ️  Using Docker-built image: $IMAGE_NAME"
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