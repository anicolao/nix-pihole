#!/bin/bash
# Comparison script showing differences between emu/ and emu2/

echo "📊 Emulation Framework Comparison: emu/ vs emu2/"
echo "================================================="
echo ""

# Check if both directories exist
if [[ ! -d "../emu" ]]; then
    echo "⚠️  emu/ directory not found"
    exit 1
fi

if [[ ! -d "." ]]; then
    echo "❌ Please run this from the emu2/ directory"
    exit 1
fi

echo "📂 Directory structure comparison:"
echo ""

echo "emu/ contents:"
ls -la ../emu/ | grep -v "^total" | sed 's/^/   /'
echo ""

echo "emu2/ contents:"
ls -la . | grep -v "^total" | sed 's/^/   /'
echo ""

# Compare script sizes
echo "📏 Script complexity comparison:"
echo ""

EMU_LINES=$(wc -l ../emu/launch-pi.sh 2>/dev/null | cut -d' ' -f1 || echo "0")
EMU2_LINES=$(wc -l launch-direct.sh 2>/dev/null | cut -d' ' -f1 || echo "0")

echo "   emu/launch-pi.sh:     $EMU_LINES lines"
echo "   emu2/launch-direct.sh: $EMU2_LINES lines"

if [[ "$EMU2_LINES" -lt "$EMU_LINES" ]]; then
    REDUCTION=$(( (EMU_LINES - EMU2_LINES) * 100 / EMU_LINES ))
    echo "   ✅ emu2/ is ${REDUCTION}% more concise"
else
    echo "   ℹ️  emu2/ has similar complexity"
fi
echo ""

# Compare approaches
echo "🔧 Technical approach comparison:"
echo ""

echo "emu/ approach:"
if grep -q "mount.*boot" ../emu/launch-pi.sh 2>/dev/null; then
    echo "   📁 Mounts SD image partitions"
else
    echo "   📁 [mount operations may be present]"
fi

if grep -q "cp.*DTB_FILE\|cp.*KERNEL_FILE" ../emu/launch-pi.sh 2>/dev/null; then
    echo "   📄 Extracts kernel and DTB files"
else
    echo "   📄 [file extraction may be present]"
fi

if grep -q "\-dtb.*\-kernel" ../emu/launch-pi.sh 2>/dev/null; then
    echo "   🚀 Boots with extracted files"
else
    echo "   🚀 [manual kernel boot may be present]"
fi

echo ""

echo "emu2/ approach:"
if ! grep -E "^[^#]*mount[[:space:]]|^[^#]*losetup|^[^#]*hdiutil.*attach" launch-direct.sh >/dev/null; then
    echo "   ✅ No file mounting or extraction"
else
    echo "   ⚠️  File operations detected"
fi

if grep -q "\-drive.*if=sd" launch-direct.sh; then
    echo "   ✅ Direct SD card boot"
else
    echo "   ❌ SD card boot not detected"
fi

if ! grep -q "\-dtb.*\-kernel" launch-direct.sh; then
    echo "   ✅ Uses image's built-in bootloader"
else
    echo "   ⚠️  Manual kernel boot detected"
fi

echo ""

# Cross-platform comparison
echo "🌍 Cross-platform support comparison:"
echo ""

echo "emu/ platform support:"
if grep -q "hdiutil" ../emu/launch-pi.sh 2>/dev/null; then
    echo "   🍎 macOS: Uses hdiutil mounting (can be unreliable)"
else
    echo "   🍎 macOS: [mounting approach unknown]"
fi

if grep -q "losetup" ../emu/launch-pi.sh 2>/dev/null; then
    echo "   🐧 Linux: Uses losetup mounting"
else
    echo "   🐧 Linux: [mounting approach unknown]"
fi

echo ""

echo "emu2/ platform support:"
echo "   🍎 macOS: Direct boot (no mounting needed)"
echo "   🐧 Linux: Direct boot (no mounting needed)"
echo "   ✅ Consistent behavior across platforms"

echo ""

# Feature comparison
echo "🎯 Feature comparison:"
echo ""

printf "%-25s | %-15s | %-15s\n" "Feature" "emu/" "emu2/"
printf "%-25s | %-15s | %-15s\n" "------------------------" "---------------" "---------------"

# Check SSH forwarding
EMU_SSH=$(grep -q "hostfwd.*ssh\|hostfwd.*22" ../emu/launch-pi.sh 2>/dev/null && echo "✅ Yes" || echo "❓ Unknown")
EMU2_SSH=$(grep -q "hostfwd.*22" launch-direct.sh && echo "✅ Yes" || echo "❌ No")
printf "%-25s | %-15s | %-15s\n" "SSH forwarding" "$EMU_SSH" "$EMU2_SSH"

# Check VNC support
EMU_VNC=$(grep -q "\-vnc" ../emu/launch-pi.sh 2>/dev/null && echo "✅ Yes" || echo "❌ No")
EMU2_VNC=$(grep -q "\-vnc" launch-direct.sh && echo "✅ Yes" || echo "❌ No")
printf "%-25s | %-15s | %-15s\n" "VNC support" "$EMU_VNC" "$EMU2_VNC"

# Check dry-run
EMU_DRY=$(grep -q "dry.*run\|DRY_RUN" ../emu/launch-pi.sh 2>/dev/null && echo "✅ Yes" || echo "❌ No")
EMU2_DRY=$(grep -q "dry.*run\|DRY_RUN" launch-direct.sh && echo "✅ Yes" || echo "❌ No")
printf "%-25s | %-15s | %-15s\n" "Dry-run mode" "$EMU_DRY" "$EMU2_DRY"

# Check memory configuration
EMU_MEM=$(grep -q "memory\|Memory" ../emu/launch-pi.sh 2>/dev/null && echo "❓ Maybe" || echo "❌ No")
EMU2_MEM=$(grep -q "memory\|Memory" launch-direct.sh && echo "✅ Yes" || echo "❌ No")
printf "%-25s | %-15s | %-15s\n" "Memory configuration" "$EMU_MEM" "$EMU2_MEM"

echo ""

# Recommendation
echo "💡 Recommendation:"
echo ""
echo "   For new projects and NixOS images: Use emu2/"
echo "   ✅ Simpler and more reliable"
echo "   ✅ Better macOS support"  
echo "   ✅ Designed for NixOS images"
echo "   ✅ Authentic hardware simulation"
echo ""
echo "   For legacy Raspberry Pi OS images: Use emu/"
echo "   ⚠️  Only if you need file extraction workflow"
echo ""

echo "🚀 Quick start with emu2/:"
echo "   1. cd emu2/"
echo "   2. nix develop"
echo "   3. ./demo-integration.sh"