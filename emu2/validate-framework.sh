#!/bin/bash
# Lightweight validation tests that don't require QEMU installation

set -e

echo "🧪 Basic Framework Validation Tests"
echo "==================================="
echo ""

# Test 1: File structure validation
echo "🧪 Test 1: File structure validation"

if [[ -f "flake.nix" ]]; then
    echo "   ✅ flake.nix present"
else
    echo "   ❌ flake.nix missing"
    exit 1
fi

if [[ -x "launch-direct.sh" ]]; then
    echo "   ✅ launch-direct.sh is executable"
else
    echo "   ❌ launch-direct.sh is not executable"
    exit 1
fi

if [[ -f "README.md" ]]; then
    echo "   ✅ README.md present"
else
    echo "   ❌ README.md missing"
    exit 1
fi

echo ""

# Test 2: Script content validation
echo "🧪 Test 2: Script content validation"

# Check that script doesn't use file extraction methods
if ! grep -E "^[^#]*mount[[:space:]]|^[^#]*losetup|^[^#]*hdiutil.*attach" launch-direct.sh; then
    echo "   ✅ No file extraction operations found"
else
    echo "   ❌ Script contains file extraction operations"
    exit 1
fi

# Check for direct boot approach
if grep -q "\-drive.*if=sd" launch-direct.sh; then
    echo "   ✅ Uses SD card direct boot approach"
else
    echo "   ❌ Does not use SD card direct boot"
    exit 1
fi

# Check for Raspberry Pi 4 configuration
if grep -q "raspi4b" launch-direct.sh; then
    echo "   ✅ Configured for Raspberry Pi 4"
else
    echo "   ❌ Not configured for Raspberry Pi 4"
    exit 1
fi

echo ""

# Test 3: Command line parsing (basic)
echo "🧪 Test 3: Basic command line parsing"

# Test help (should not require QEMU)
if ./launch-direct.sh --help | grep -q "Usage:"; then
    echo "   ✅ Help option works"
else
    echo "   ❌ Help option failed"
    exit 1
fi

echo ""

# Test 4: Cross-platform design
echo "🧪 Test 4: Cross-platform design validation"

# Check flake.nix supports multiple systems
if grep -q "x86_64-darwin\|aarch64-darwin" flake.nix; then
    echo "   ✅ Flake supports macOS"
else
    echo "   ❌ Flake does not support macOS"
    exit 1
fi

if grep -q "x86_64-linux\|aarch64-linux" flake.nix; then
    echo "   ✅ Flake supports Linux"
else
    echo "   ❌ Flake does not support Linux"
    exit 1
fi

echo ""

# Test 5: Documentation quality
echo "🧪 Test 5: Documentation validation"

if grep -q "No file extraction" README.md; then
    echo "   ✅ Documents direct boot advantage"
else
    echo "   ❌ Missing direct boot documentation"
    exit 1
fi

if grep -q "macOS\|cross-platform" README.md; then
    echo "   ✅ Documents cross-platform support"
else
    echo "   ❌ Missing cross-platform documentation"
    exit 1
fi

echo ""

# Final summary
echo "🎉 All basic validation tests passed!"
echo ""
echo "The emu2/ framework structure and design are correct."
echo ""
echo "Next steps:"
echo "1. Run 'nix develop' to enter the development environment"
echo "2. Build a NixOS image from the repository root"
echo "3. Test the emulation with a real image"
echo ""
echo "Framework features verified:"
echo "  ✅ Direct boot design (no file extraction)"
echo "  ✅ Cross-platform support (macOS/Linux)"
echo "  ✅ Raspberry Pi 4 target configuration"
echo "  ✅ Proper documentation and help"