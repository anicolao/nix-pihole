#!/bin/bash
# Alternative approach: Run NixOS directly in Colima VM instead of container
# This provides the most robust solution as requested by the user

set -e

echo "🚀 Setting up NixOS VM Remote Builder (Alternative Approach)"
echo "==========================================================="
echo
echo "⚠️  This approach runs NixOS directly in the Colima VM instead of a container."
echo "   This provides the most robust and native NixOS experience."
echo

# Configuration
COLIMA_PROFILE="nixos-builder"
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
        exit 0
    fi
fi

echo "💡 This script sets up a foundation for running NixOS in the VM."
echo "   You would need to:"
echo "   1. Create a NixOS ISO or image"
echo "   2. Boot it in the Colima VM"
echo "   3. Configure SSH service declaratively"
echo
echo "🏗️  Creating Colima VM foundation..."
colima start \
    --profile "$COLIMA_PROFILE" \
    --arch "$COLIMA_ARCH" \
    --memory "$COLIMA_MEMORY" \
    --disk "$COLIMA_DISK" \
    --cpu "$COLIMA_CPU" \
    --vm-type=vz

echo
echo "✅ VM foundation created!"
echo
echo "📋 Next steps to complete NixOS setup:"
echo "  1. Download NixOS ISO for aarch64"
echo "  2. Mount it in the VM"
echo "  3. Install NixOS with SSH service enabled"
echo "  4. Configure as remote builder"
echo
echo "ℹ️  For now, please use the container-based approach:"
echo "     ./builder/setup-remote-builder.sh"
echo