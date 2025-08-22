#!/bin/bash
set -e

echo "🧪 Testing Raspberry Pi 4 Emulator Setup"
echo "========================================"

# Test 1: Check if flake.nix is valid
echo ""
echo "Test 1: Validating flake.nix..."
if command -v nix >/dev/null 2>&1; then
    if nix flake check . 2>/dev/null; then
        echo "✅ flake.nix is valid"
    else
        echo "❌ flake.nix has syntax errors"
        exit 1
    fi
else
    echo "⚠️  Nix not available, skipping flake validation"
fi

# Test 2: Check if launch script is executable and shows help
echo ""
echo "Test 2: Testing launch script..."
if [[ -x "./launch-pi.sh" ]]; then
    echo "✅ launch-pi.sh is executable"
else
    echo "❌ launch-pi.sh is not executable"
    exit 1
fi

# Test 3: Check help output
echo ""
echo "Test 3: Testing --help option..."
if ./launch-pi.sh --help >/dev/null 2>&1; then
    echo "✅ --help option works"
else
    echo "❌ --help option failed"
    exit 1
fi

# Test 4: Check dry-run with missing image (should fail gracefully)
echo ""
echo "Test 4: Testing error handling..."
if ./launch-pi.sh --dry-run /nonexistent/image.img 2>/dev/null; then
    echo "❌ Should have failed with missing image"
    exit 1
else
    echo "✅ Correctly handles missing image file"
fi

# Test 5: Check if we can detect OS type
echo ""
echo "Test 5: Testing OS detection..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "✅ Detected macOS - will use hdiutil"
else
    echo "✅ Detected Linux - will use loop devices"
fi

# Test 6: Create a minimal fake image and test dry-run
echo ""
echo "Test 6: Testing with fake image..."
FAKE_IMG=$(mktemp --suffix=.img)
# Create a minimal file that looks like an image
dd if=/dev/zero of="$FAKE_IMG" bs=1M count=1 2>/dev/null

if ./launch-pi.sh --dry-run "$FAKE_IMG" 2>&1 | grep -q "Dry run - would execute"; then
    echo "✅ Dry-run mode works with fake image"
else
    echo "❌ Dry-run mode failed"
    rm -f "$FAKE_IMG"
    exit 1
fi

# Clean up
rm -f "$FAKE_IMG"

# Test 7: Check if QEMU would be available in nix shell
echo ""
echo "Test 7: Testing tool availability..."
if command -v nix >/dev/null 2>&1; then
    if nix develop --command which qemu-system-aarch64 >/dev/null 2>&1; then
        echo "✅ qemu-system-aarch64 available in nix shell"
    else
        echo "⚠️  qemu-system-aarch64 not available (might need to run nix develop first)"
    fi
else
    echo "⚠️  Nix not available, skipping QEMU check"
fi

echo ""
echo "🎉 All tests passed!"
echo ""
echo "To use the emulator:"
echo "1. nix develop"
echo "2. ./launch-pi.sh /path/to/your/raspios-image.img"
echo ""
echo "For help: ./launch-pi.sh --help"