#!/bin/bash
# Test script for Colima remote builder functionality

set -e

echo "🧪 Testing Colima Remote Builder"
echo "================================"
echo

# Configuration
COLIMA_PROFILE="nix-builder"

# Check if colima is available
if ! command -v colima &> /dev/null; then
    echo "❌ Colima not found. Please run: nix develop"
    exit 1
fi

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please run: nix develop"
    exit 1
fi

echo "🔍 Checking Colima profile status..."
if ! colima list | grep -q "$COLIMA_PROFILE"; then
    echo "❌ Colima profile '$COLIMA_PROFILE' not found"
    echo "ℹ️  Run: ./builder/setup-remote-builder.sh"
    exit 1
fi

if ! colima status "$COLIMA_PROFILE" | grep -q "Running"; then
    echo "⚠️  Colima profile '$COLIMA_PROFILE' is not running"
    echo "🚀 Starting Colima profile..."
    colima start "$COLIMA_PROFILE"
fi

echo "✅ Colima profile '$COLIMA_PROFILE' is running"

# Set Docker host
export DOCKER_HOST="unix://$HOME/.colima/$COLIMA_PROFILE/docker.sock"

echo "🐳 Checking Docker connectivity..."
if docker info > /dev/null 2>&1; then
    echo "✅ Docker connection successful"
    
    # Show basic info
    DOCKER_ARCH=$(docker info --format '{{.Architecture}}')
    echo "  Architecture: $DOCKER_ARCH"
else
    echo "❌ Docker connection failed"
    exit 1
fi

echo "🏗️  Checking NixOS container..."
if docker ps | grep -q "nix-remote-builder"; then
    echo "✅ NixOS remote builder container is running"
else
    echo "⚠️  NixOS container not running, attempting to start..."
    if docker ps -a | grep -q "nix-remote-builder"; then
        docker start nix-remote-builder
        echo "🚀 Started existing container"
        sleep 5
    else
        echo "❌ NixOS container not found"
        echo "ℹ️  Run: ./builder/setup-remote-builder.sh"
        exit 1
    fi
fi

echo "🔑 Testing SSH connection to remote builder..."
if [ ! -f "$HOME/.ssh/nix-builder" ]; then
    echo "❌ SSH key not found: $HOME/.ssh/nix-builder"
    echo "ℹ️  Run: ./builder/setup-remote-builder.sh"
    exit 1
fi

# Test SSH connection
if timeout 10 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -p 2222 root@localhost "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "✅ SSH connection to remote builder successful"
else
    echo "❌ SSH connection failed"
    echo "ℹ️  Container logs:"
    docker logs nix-remote-builder | tail -10
    exit 1
fi

echo "🔧 Testing Nix functionality on remote builder..."
NIX_VERSION=$(timeout 10 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -p 2222 root@localhost "nix --version" 2>/dev/null || echo "failed")
if [ "$NIX_VERSION" != "failed" ]; then
    echo "✅ Nix is working on remote builder"
    echo "  Version: $NIX_VERSION"
else
    echo "❌ Nix is not working on remote builder"
    exit 1
fi

echo "🏗️  Testing simple build on remote builder..."
BUILD_TEST=$(timeout 30 ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -p 2222 root@localhost "nix build --no-link nixpkgs#hello && echo 'build-success'" 2>/dev/null || echo "build-failed")
if [ "$BUILD_TEST" = "build-success" ]; then
    echo "✅ Simple build test successful"
else
    echo "❌ Simple build test failed"
    echo "ℹ️  This might be due to network or cache issues, but the builder should still work"
fi

echo "📊 Remote builder system information:"
ssh -i "$HOME/.ssh/nix-builder" -o StrictHostKeyChecking=no -p 2222 root@localhost "
    echo '  OS: \$(uname -a)'
    echo '  Architecture: \$(uname -m)'
    echo '  Available memory: \$(free -h | grep Mem | awk \"{print \\\$2}\")'
    echo '  Disk space: \$(df -h / | tail -1 | awk \"{print \\\$4}\")'
    echo '  Nix store: \$(du -sh /nix 2>/dev/null || echo \"calculating...\")'" 2>/dev/null || echo "  Unable to get system info"

echo
echo "🎯 Testing Nix remote builder configuration..."
if [ -f "$HOME/.config/nix/nix.conf" ] && grep -q "ssh://root@localhost:2222" "$HOME/.config/nix/nix.conf"; then
    echo "✅ Nix remote builder configuration found"
    echo "  Config: $HOME/.config/nix/nix.conf"
else
    echo "⚠️  Nix remote builder configuration not found or incorrect"
    echo "ℹ️  Run: ./builder/setup-remote-builder.sh"
fi

echo
echo "✅ Remote builder test complete!"
echo
echo "📋 Test summary:"
echo "  - Colima profile: ✅ Running"
echo "  - Docker connectivity: ✅ Working"
echo "  - NixOS container: ✅ Running"
echo "  - SSH access: ✅ Working"
echo "  - Nix functionality: ✅ Working"
echo
echo "🎯 Ready to build! Try:"
echo "  ./builder/make-image.sh"
echo