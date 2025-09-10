#!/bin/bash
# Simple validation script to test the remote builder setup

set -e

echo "🧪 Validating Remote Builder Setup"
echo "=================================="
echo

# Test 1: Check if we're in the right directory
echo "1. 📁 Checking repository structure..."
if [ ! -f "flake.nix" ]; then
    echo "❌ flake.nix not found - please run from repository root"
    exit 1
fi

if [ ! -d "builder" ]; then
    echo "❌ builder/ directory not found"
    exit 1
fi

echo "✅ Repository structure looks good"

# Test 2: Check script permissions
echo "2. 🔧 Checking script permissions..."
for script in setup-remote-builder.sh test-remote-builder.sh make-image.sh; do
    if [ ! -x "builder/$script" ]; then
        echo "❌ $script is not executable"
        exit 1
    fi
done
echo "✅ All scripts are executable"

# Test 3: Check flake structure (basic syntax)
echo "3. 📋 Validating flake.nix structure..."
if grep -q "Pi-hole RPi4 Image Builder with Remote Builder Support" flake.nix; then
    echo "✅ Flake description updated"
else
    echo "❌ Flake description not found"
    exit 1
fi

if grep -q "devShells.default" flake.nix; then
    echo "✅ Development shell defined"
else
    echo "❌ Development shell not found in flake.nix"
    exit 1
fi

if grep -q "colima" flake.nix; then
    echo "✅ Colima dependency included"
else
    echo "❌ Colima not found in flake.nix"
    exit 1
fi

# Test 4: Check if required tools would be available (in a nix develop environment)
echo "4. 🛠️  Checking development environment requirements..."
echo "   Note: These tools should be available after running 'nix develop'"

REQUIRED_TOOLS=("colima" "docker" "docker-compose" "curl" "jq" "ssh")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if grep -q "$tool" flake.nix; then
        echo "   ✅ $tool listed in buildInputs"
    else
        echo "   ⚠️  $tool not explicitly found in flake.nix"
    fi
done

# Test 5: Check documentation
echo "5. 📚 Checking documentation..."
if [ -f "builder/README.md" ]; then
    echo "✅ Builder README.md exists"
    
    if grep -q "Remote Builder for Pi-hole NixOS Images" builder/README.md; then
        echo "✅ Builder README has proper title"
    else
        echo "❌ Builder README title not found"
        exit 1
    fi
else
    echo "❌ builder/README.md not found"
    exit 1
fi

if grep -q "Option A: Using Remote Builder" README.md; then
    echo "✅ Main README updated with remote builder info"
else
    echo "❌ Main README not updated with remote builder information"
    exit 1
fi

# Test 6: Check script content for key functionality
echo "6. 🔍 Validating script content..."

if grep -q "COLIMA_PROFILE.*nix-builder" builder/setup-remote-builder.sh; then
    echo "✅ Setup script has correct Colima profile name"
else
    echo "❌ Setup script missing Colima profile configuration"
    exit 1
fi

if grep -q "ssh://root@localhost:2222" builder/test-remote-builder.sh; then
    echo "✅ Test script has correct SSH configuration"
else
    echo "❌ Test script missing SSH configuration"
    exit 1
fi

if grep -q "images.rpi4" builder/make-image.sh; then
    echo "✅ Make script targets correct image"
else
    echo "❌ Make script missing image target"
    exit 1
fi

echo
echo "✅ All validation checks passed!"
echo
echo "🎯 Next steps:"
echo "1. Run 'nix develop' to enter the development environment"
echo "2. Run './builder/setup-remote-builder.sh' to set up the remote builder"
echo "3. Run './builder/test-remote-builder.sh' to test the setup"
echo "4. Run './builder/make-image.sh' to build the Pi-hole image"
echo
echo "📚 Documentation:"
echo "- builder/README.md - Detailed remote builder documentation"
echo "- README.md - Updated main documentation with remote builder info"
echo