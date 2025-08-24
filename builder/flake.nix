{
  description = "Pi-hole RPi4 Image Builder with Remote Builder Support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core dependencies for remote builder
            colima
            docker
            docker-compose
            
            # Nix tools
            nix
            
            # Utilities
            coreutils
            bash
            curl
            jq
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOS specific packages if needed
          ];

          shellHook = ''
            echo "Pi-hole RPi4 Image Builder Environment"
            echo "======================================"
            echo
            echo "Available commands:"
            echo "  ./builder/make-image.sh   - Build the RPi4 image using remote builder"
            echo "  ./builder/setup-remote-builder.sh - Set up Colima remote builder"
            echo "  ./builder/test-remote-builder.sh  - Test remote builder functionality"
            echo
            echo "Quick start:"
            echo "  ./builder/make-image.sh"
            echo
          '';
        };
      });
}