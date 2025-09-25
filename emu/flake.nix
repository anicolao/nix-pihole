{
  description = "A reproducible QEMU environment for Raspberry Pi emulation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    # Support multiple systems
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages =
            [
              # The core emulator for ARM64 systems
              pkgs.qemu_full
              pkgs.util-linux
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              # macOS-specific tools are handled by the system
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              # Linux-specific tools for image mounting
              pkgs.kpartx
              pkgs.mount
              # Add utilities for image manipulation
              pkgs.parted
            ];

          shellHook = ''
            echo "🚀 Raspberry Pi 4 Emulation Environment Ready!"
            echo "   Run: ./launch-pi.sh /path/to/your/raspios-image.img"
            echo "   Or: ./launch-pi.sh --help for more information"
            echo ""
            echo "Available tools:"
            echo "  - qemu-system-aarch64: ARM64 emulator"
            echo "  - parted: Partition table manipulation"
            ${
              if pkgs.stdenv.isLinux
              then ''
                echo "  - kpartx: Loop device partition mapping (Linux)"
              ''
              else ''
                echo "  - hdiutil: Disk image utilities (macOS)"
              ''
            }
          '';
        };
      }
    );
  };
}

