{
  description = "Direct-boot QEMU environment for NixOS Raspberry Pi images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Support multiple systems - especially important for macOS support
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              # QEMU with full ARM support and firmware
              pkgs.qemu_full
              # Include QEMU firmware for proper EFI/UEFI support
              pkgs.qemu-utils
              # UEFI firmware for ARM64 emulation
              pkgs.OVMF
              # Basic utilities 
              pkgs.file
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              # macOS typically has hdiutil built-in
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              # Linux utilities for inspection (optional)
              pkgs.util-linux
            ];
            
            shellHook = ''
              echo "🚀 Direct-Boot Raspberry Pi Emulation Environment Ready!"
              echo ""
              echo "This environment boots NixOS images directly without file extraction."
              echo "Perfect for images built by this repository's flake.nix"
              echo ""
              echo "Usage:"
              echo "  ./launch-direct.sh /path/to/nixos-rpi4-image.img"
              echo "  ./launch-direct.sh --machine uefi --console firmware /path/to/modern-pi4-image.img"
              echo "  ./launch-direct.sh --help for more options"
              echo ""
              echo "Available tools:"
              echo "  - qemu-system-aarch64: ARM64 emulator with full firmware support"
              echo "  - UEFI firmware (OVMF): For modern Pi4 UEFI images"
              echo "  - file: File type detection"
              ${if pkgs.stdenv.isDarwin then ''
              echo "  - Running on macOS with native support"
              '' else ''
              echo "  - Running on Linux"
              ''}
              echo ""
              echo "Key advantages over emu/:"
              echo "  ✅ No file extraction needed"
              echo "  ✅ Boots like real hardware via U-Boot or UEFI"
              echo "  ✅ Works with NixOS SD images"
              echo "  ✅ UEFI support for modern Pi4 images"
              echo "  ✅ Cross-platform (macOS/Linux)"
              echo ""
              echo "For modern Pi4 NixOS images with UEFI:"
              echo "  Use --machine uefi option for best compatibility"
            '';
          };
        }
      );
    };
}