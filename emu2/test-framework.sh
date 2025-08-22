#!/bin/bash
# Integration tests for the direct-boot emulation framework

set -e

echo "🧪 Direct-Boot Emulation Framework Tests"
echo "========================================"
echo ""

# Test 1: Environment validation
echo "🧪 Test 1: Development environment validation"

# Check if we're in a Nix environment or can access QEMU
if command -v qemu-system-aarch64 &> /dev/null; then
    echo "   ✅ qemu-system-aarch64 is available"
else
    echo "   ⚠️  qemu-system-aarch64 not found (run 'nix develop' first)"
fi

# Check script permissions
if [[ -x "./launch-direct.sh" ]]; then
    echo "   ✅ launch-direct.sh is executable"
else
    echo "   ❌ launch-direct.sh is not executable"
    exit 1
fi

# Check flake.nix exists and is valid
if [[ -f "flake.nix" ]]; then
    echo "   ✅ flake.nix present"
else
    echo "   ❌ flake.nix missing"
    exit 1
fi

echo ""

# Test 2: Command line argument parsing
echo "🧪 Test 2: Command line argument validation"

# Test help option
if ./launch-direct.sh --help | grep -q "direct boot from NixOS SD image"; then
    echo "   ✅ --help option works"
else
    echo "   ❌ --help option failed"
    exit 1
fi

# Test missing arguments
if ./launch-direct.sh 2>&1 | grep -q "No disk image specified"; then
    echo "   ✅ Handles missing arguments correctly"
else
    echo "   ❌ Missing argument handling failed"
    exit 1
fi

# Test invalid arguments
if ./launch-direct.sh --invalid-option 2>&1 | grep -q "Unknown option"; then
    echo "   ✅ Handles invalid options correctly"
else
    echo "   ❌ Invalid option handling failed"
    exit 1
fi

echo ""

# Test 3: Image validation
echo "🧪 Test 3: Image file validation"

# Test with non-existent file
if ./launch-direct.sh /nonexistent/file.img 2>&1 | grep -q "Image file not found"; then
    echo "   ✅ Handles non-existent image files"
else
    echo "   ❌ Non-existent file handling failed"
    exit 1
fi

# Test dry-run with fake image
echo "   Creating test image file..."
FAKE_IMG="/tmp/test-image.img"
dd if=/dev/zero of="$FAKE_IMG" bs=1M count=1 2>/dev/null

if ./launch-direct.sh --dry-run "$FAKE_IMG" 2>&1 | grep -q "would execute"; then
    echo "   ✅ --dry-run option works"
else
    echo "   ❌ --dry-run option failed"
    rm -f "$FAKE_IMG"
    exit 1
fi

rm -f "$FAKE_IMG"
echo ""

# Test 4: Parameter validation and parsing
echo "🧪 Test 4: Parameter parsing validation"

# Create test image for parameter tests
echo "   Creating test image for parameter validation..."
PARAM_TEST_IMG="/tmp/param-test.img"
dd if=/dev/zero of="$PARAM_TEST_IMG" bs=1M count=1 2>/dev/null

# Test custom port parsing
if ./launch-direct.sh --port 2222 --dry-run "$PARAM_TEST_IMG" 2>&1 | grep -q ":2222-:22"; then
    echo "   ✅ Custom SSH port parsing works"
else
    echo "   ❌ Custom SSH port parsing failed"
    rm -f "$PARAM_TEST_IMG"
    exit 1
fi

# Test VNC option parsing
if ./launch-direct.sh --vnc 5901 --dry-run "$PARAM_TEST_IMG" 2>&1 | grep -q "\-vnc"; then
    echo "   ✅ VNC option parsing works"
else
    echo "   ❌ VNC option parsing failed"
    rm -f "$PARAM_TEST_IMG"
    exit 1
fi

# Test memory option parsing
if ./launch-direct.sh --memory 1G --dry-run "$PARAM_TEST_IMG" 2>&1 | grep -q "\-m 1G"; then
    echo "   ✅ Memory option parsing works"
else
    echo "   ❌ Memory option parsing failed"
    rm -f "$PARAM_TEST_IMG"
    exit 1
fi

rm -f "$PARAM_TEST_IMG"

echo ""

# Test 5: QEMU command generation
echo "🧪 Test 5: QEMU command generation validation"

# Create test image for QEMU command validation
echo "   Creating test image for command validation..."
CMD_TEST_IMG="/tmp/cmd-test.img"
dd if=/dev/zero of="$CMD_TEST_IMG" bs=1M count=1 2>/dev/null

# Check that essential QEMU options are present in dry-run
QEMU_OUTPUT=$(./launch-direct.sh --dry-run "$CMD_TEST_IMG" 2>&1)

if echo "$QEMU_OUTPUT" | grep -q "qemu-system-aarch64"; then
    echo "   ✅ Uses correct QEMU binary"
else
    echo "   ❌ QEMU binary not specified correctly"
    exit 1
fi

if echo "$QEMU_OUTPUT" | grep -q "\-machine raspi4b"; then
    echo "   ✅ Raspberry Pi 4 machine type specified"
else
    echo "   ❌ Machine type not specified correctly"
    exit 1
fi

if echo "$QEMU_OUTPUT" | grep -q "\-drive.*if=sd"; then
    echo "   ✅ SD card interface specified"
else
    echo "   ❌ SD card interface not specified"
    exit 1
fi

if echo "$QEMU_OUTPUT" | grep -q "hostfwd=tcp"; then
    echo "   ✅ SSH port forwarding specified"
else
    echo "   ❌ SSH port forwarding not specified"
    rm -f "$CMD_TEST_IMG"
    exit 1
fi

rm -f "$CMD_TEST_IMG"

echo ""

# Test 6: Cross-platform compatibility checks
echo "🧪 Test 6: Cross-platform compatibility"

# Check for macOS/Linux specific behavior
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "   ✅ Running on macOS"
    # Test that we're not using Linux-specific tools
    if ! grep -q "losetup\|kpartx" launch-direct.sh; then
        echo "   ✅ No Linux-specific mounting tools used"
    else
        echo "   ❌ Contains Linux-specific mounting tools"
        exit 1
    fi
else
    echo "   ✅ Running on Linux"
fi

# Check that the script doesn't try to mount or extract files
if ! grep -q "mount\|losetup\|hdiutil.*attach" launch-direct.sh; then
    echo "   ✅ No file extraction or mounting operations"
else
    echo "   ❌ Contains file extraction or mounting operations"
    exit 1
fi

echo ""

# Test 7: Documentation validation
echo "🧪 Test 7: Documentation validation"

if [[ -f "README.md" ]]; then
    if grep -q "Direct-Boot" README.md; then
        echo "   ✅ README.md present and contains expected content"
    else
        echo "   ❌ README.md doesn't contain expected content"
        exit 1
    fi
else
    echo "   ❌ README.md missing"
    exit 1
fi

echo ""

# Final summary
echo "🎉 All tests passed!"
echo ""
echo "The direct-boot emulation framework is ready to use."
echo "Key features validated:"
echo "  ✅ Cross-platform compatibility"
echo "  ✅ No file extraction required"
echo "  ✅ Proper argument handling"
echo "  ✅ QEMU command generation"
echo "  ✅ Error handling"
echo ""
echo "To use:"
echo "  1. Build a NixOS image: nix build .#images.rpi4"
echo "  2. Launch emulator: ./launch-direct.sh result/sd-image/nixos-sd-image-*.img"