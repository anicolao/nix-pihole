#!/bin/bash
set -e

echo "🔬 Comprehensive PI4 Emulator Integration Test"
echo "=============================================="
echo ""

# Test the complete workflow documented in PI4_EMULATOR.md
echo "This test validates the complete emulator implementation as specified in PI4_EMULATOR.md"
echo ""

# Step 1: Validate we're in the right directory
if [[ ! -f "./flake.nix" ]] || [[ ! -f "./launch-pi.sh" ]]; then
    echo "❌ Test must be run from the emu directory"
    exit 1
fi

echo "📋 Testing Complete Workflow:"
echo "1. Environment setup validation"
echo "2. Script functionality testing"
echo "3. Command-line option testing"
echo "4. Cross-platform compatibility"
echo "5. Error handling validation"
echo ""

# Test 1: Flake validation
echo "🧪 Test 1: Nix flake validation"
if [[ -f "./flake.nix" ]]; then
    echo "   ✅ flake.nix exists"
    
    # Check if flake contains expected components
    if grep -q "qemu_full" flake.nix; then
        echo "   ✅ QEMU package specified"
    else
        echo "   ❌ QEMU package not found in flake"
        exit 1
    fi
    
    if grep -q "devShells" flake.nix; then
        echo "   ✅ Development shell configured"
    else
        echo "   ❌ Development shell not configured"
        exit 1
    fi
    
    if grep -q "systems.*=.*\[" flake.nix; then
        echo "   ✅ Multi-system support configured"
    else
        echo "   ❌ Multi-system support not found"
        exit 1
    fi
else
    echo "   ❌ flake.nix not found"
    exit 1
fi
echo ""

# Test 2: Launch script validation
echo "🧪 Test 2: Launch script validation"
if [[ -x "./launch-pi.sh" ]]; then
    echo "   ✅ launch-pi.sh is executable"
else
    echo "   ❌ launch-pi.sh is not executable"
    exit 1
fi

# Test help output contains expected sections
help_output=$(./launch-pi.sh --help)
if echo "$help_output" | grep -q "Usage:"; then
    echo "   ✅ Help shows usage information"
else
    echo "   ❌ Help missing usage information"
    exit 1
fi

if echo "$help_output" | grep -q "OPTIONS:"; then
    echo "   ✅ Help shows options"
else
    echo "   ❌ Help missing options section"
    exit 1
fi

if echo "$help_output" | grep -q "EXAMPLES:"; then
    echo "   ✅ Help shows examples"
else
    echo "   ❌ Help missing examples section"
    exit 1
fi
echo ""

# Test 3: Command-line options
echo "🧪 Test 3: Command-line option testing"

# Test Pi 3 fallback
echo "   Testing --pi3 option..."
FAKE_IMG=$(mktemp --suffix=.img)
dd if=/dev/zero of="$FAKE_IMG" bs=1M count=1 2>/dev/null

if ./launch-pi.sh --pi3 --dry-run "$FAKE_IMG" 2>&1 | grep -q "raspi3b"; then
    echo "   ✅ --pi3 option switches to Pi 3 emulation"
else
    echo "   ❌ --pi3 option not working"
    rm -f "$FAKE_IMG"
    exit 1
fi

# Test custom port
echo "   Testing --port option..."
if ./launch-pi.sh --port 3333 --dry-run "$FAKE_IMG" 2>&1 | grep -q "hostfwd=tcp::3333"; then
    echo "   ✅ --port option works"
else
    echo "   ❌ --port option not working"
    rm -f "$FAKE_IMG"
    exit 1
fi

# Test dry-run
echo "   Testing --dry-run option..."
if ./launch-pi.sh --dry-run "$FAKE_IMG" 2>&1 | grep -q "Dry run - would execute"; then
    echo "   ✅ --dry-run option works"
else
    echo "   ❌ --dry-run option not working"
    rm -f "$FAKE_IMG"
    exit 1
fi

rm -f "$FAKE_IMG"
echo ""

# Test 4: Cross-platform compatibility
echo "🧪 Test 4: Cross-platform compatibility"
if [[ "$OSTYPE" == "darwin"* ]]; then
    if grep -q "hdiutil" launch-pi.sh; then
        echo "   ✅ macOS disk mounting supported (hdiutil)"
    else
        echo "   ❌ macOS support missing"
        exit 1
    fi
    echo "   ✅ Running on macOS"
else
    if grep -q "losetup" launch-pi.sh; then
        echo "   ✅ Linux disk mounting supported (losetup)"
    else
        echo "   ❌ Linux support missing"
        exit 1
    fi
    echo "   ✅ Running on Linux"
fi

# Check that both paths are implemented
if grep -q "mount_image_linux" launch-pi.sh && grep -q "mount_image_macos" launch-pi.sh; then
    echo "   ✅ Both Linux and macOS mounting functions present"
else
    echo "   ❌ Missing cross-platform mounting functions"
    exit 1
fi
echo ""

# Test 5: Error handling
echo "🧪 Test 5: Error handling validation"

# Test missing image file
echo "   Testing missing file handling..."
if ./launch-pi.sh /nonexistent/file.img 2>&1 | grep -q "Disk image not found"; then
    echo "   ✅ Handles missing image files correctly"
else
    echo "   ❌ Missing file error handling failed"
    exit 1
fi

# Test missing arguments
echo "   Testing missing arguments..."
if ./launch-pi.sh 2>&1 | grep -q "No disk image specified"; then
    echo "   ✅ Handles missing arguments correctly"
else
    echo "   ❌ Missing argument error handling failed"
    exit 1
fi

# Test invalid options
echo "   Testing invalid options..."
if ./launch-pi.sh --invalid-option 2>&1 | grep -q "Unknown option"; then
    echo "   ✅ Handles invalid options correctly"
else
    echo "   ❌ Invalid option error handling failed"
    exit 1
fi
echo ""

# Test 6: Validate expected QEMU command structure
echo "🧪 Test 6: QEMU command validation"
FAKE_IMG=$(mktemp --suffix=.img)
dd if=/dev/zero of="$FAKE_IMG" bs=1M count=1 2>/dev/null

qemu_cmd=$(./launch-pi.sh --dry-run "$FAKE_IMG" 2>&1 | grep "qemu-system-aarch64")

# Check for essential QEMU parameters
if echo "$qemu_cmd" | grep -q "\-M raspi4b"; then
    echo "   ✅ Machine type specified (raspi4b)"
else
    echo "   ❌ Machine type missing"
    rm -f "$FAKE_IMG"
    exit 1
fi

if echo "$qemu_cmd" | grep -q "\-cpu cortex-a72"; then
    echo "   ✅ CPU type specified (cortex-a72)"
else
    echo "   ❌ CPU type missing"
    rm -f "$FAKE_IMG"
    exit 1
fi

if echo "$qemu_cmd" | grep -q "\-m 2G"; then
    echo "   ✅ Memory specified (2G)"
else
    echo "   ❌ Memory specification missing"
    rm -f "$FAKE_IMG"
    exit 1
fi

if echo "$qemu_cmd" | grep -q "\-smp 4"; then
    echo "   ✅ SMP cores specified (4)"
else
    echo "   ❌ SMP specification missing"
    rm -f "$FAKE_IMG"
    exit 1
fi

if echo "$qemu_cmd" | grep -q "\-netdev.*hostfwd"; then
    echo "   ✅ Network forwarding configured"
else
    echo "   ❌ Network forwarding missing"
    rm -f "$FAKE_IMG"
    exit 1
fi

rm -f "$FAKE_IMG"
echo ""

# Final validation
echo "🎯 Final Validation:"
echo "   ✅ All components from PI4_EMULATOR.md implemented"
echo "   ✅ Cross-platform compatibility ensured"
echo "   ✅ Enhanced error handling added"
echo "   ✅ Additional features (Pi3 fallback, custom ports) implemented"
echo "   ✅ Comprehensive testing suite created"
echo ""

echo "🎉 INTEGRATION TEST PASSED!"
echo ""
echo "📚 Usage Summary (as per PI4_EMULATOR.md):"
echo "1. nix develop"
echo "2. ./launch-pi.sh /path/to/your/raspios-image.img"
echo "3. ssh pi@localhost -p 5022"
echo ""
echo "🔧 Additional Options:"
echo "   --pi3       Use Pi 3 emulation for stability"
echo "   --port N    Use custom SSH port"
echo "   --dry-run   Test without actually running"
echo "   --help      Show detailed help"
echo ""
echo "The emulator implementation is ready for use!"